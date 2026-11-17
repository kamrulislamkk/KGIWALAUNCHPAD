// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {KgiwaLaunchpadTestBase, Ref, TI} from "./KgiwaLaunchpad.Base.t.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";

contract KgiwaLaunchpadFeesTest is KgiwaLaunchpadTestBase {
    LaunchToken internal t;

    function setUp() public override {
        super.setUp();
        t = _create(200); // 2%
    }

    function _findLog(Vm.Log[] memory logs, bytes32 sig) internal pure returns (Vm.Log memory out, bool found) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) {
                out = logs[i];
                found = true;
            }
        }
    }

    // ---- (6) fee accounting on buy

    struct Parsed {
        uint256 p; uint256 c; uint256 h; uint256 b; uint256 tradeFee; uint256 burnEth; uint256 burnTokens;
    }

    function _parse(Vm.Log[] memory logs) internal view returns (Parsed memory r) {
        (Vm.Log memory fd, bool f1) = _findLog(logs, KgiwaLaunchpad.FeesDistributed.selector);
        assertTrue(f1, "FeesDistributed");
        (r.p, r.c, r.h, r.b) = abi.decode(fd.data, (uint256, uint256, uint256, uint256));
        assertEq(address(uint160(uint256(fd.topics[1]))), address(t));
        (Vm.Log memory tl, bool f2) = _findLog(logs, KgiwaLaunchpad.Trade.selector);
        assertTrue(f2, "Trade");
        (,,, r.tradeFee,) = abi.decode(tl.data, (bool, uint256, uint256, uint256, uint256));
        (Vm.Log memory bl, bool f3) = _findLog(logs, KgiwaLaunchpad.Burned.selector);
        assertTrue(f3, "Burned");
        (r.burnEth, r.burnTokens) = abi.decode(bl.data, (uint256, uint256));
    }

    function test_BuyFeeSplit20_20_20_Remainder() public {
        uint256 platBefore = platform.balance;
        uint256 supplyBefore = t.totalSupply();
        uint256 sold0 = _sold(t);
        vm.recordLogs();
        uint256 got = _buy(alice, t, 10 ether);
        Parsed memory r = _parse(vm.getRecordedLogs());

        assertEq(platform.balance - platBefore, 0.08 ether, "platform paid immediately");
        assertEq(lp.creatorFees(address(t)), 0.04 ether, "creator 20%");
        assertEq(lp.holderPool(address(t)), 0.04 ether, "holders 20%");
        assertEq(r.p, 0.08 ether);
        assertEq(r.c, 0.04 ether);
        assertEq(r.h, 0.04 ether);
        assertEq(r.b, 0.04 ether);
        assertEq(r.p + r.c + r.h + r.b, 0.2 ether, "four parts sum to fee");
        assertEq(r.tradeFee, 0.2 ether, "Trade.fee is total F");

        // burn: real curve purchase, reserve + burn ETH, supply down by burned tokens
        assertEq(r.burnEth, 0.04 ether);
        assertGt(r.burnTokens, 0);
        assertEq(supplyBefore - t.totalSupply(), r.burnTokens, "totalSupply drops by burned tokens");
        assertEq(_info(t).reserve, 9.8 ether + 0.04 ether, "reserve += net + burn ETH");
        assertEq(_info(t).inv, CURVE - sold0 - got - r.burnTokens, "inventory decreases by bought + burned");
        assertApproxEqAbs(
            r.burnTokens, Ref.position(sold0 + got, 0.04 ether) - (sold0 + got), TOKEN_TOL, "burn priced on the curve"
        );
        _assertBacked(t);
        _assertLedger();
    }

    function test_SellFeeSplitAndLedger() public {
        uint256 got = _buy(alice, t, 10 ether);
        (uint256 q, uint256 fee,) = lp.quoteSellDetail(address(t), got);
        uint256 platBefore = platform.balance;
        uint256 poolBefore = lp.holderPool(address(t));
        uint256 cfBefore = lp.creatorFees(address(t));
        _buy(bob, t, 1 ether); // keep circulating > 1000 tokens after alice exits
        poolBefore = lp.holderPool(address(t));
        cfBefore = lp.creatorFees(address(t));
        platBefore = platform.balance;
        (q, fee,) = lp.quoteSellDetail(address(t), got);
        vm.recordLogs();
        uint256 out = _sell(alice, t, got);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(out, q);
        uint256 share = fee * 20 / 100;
        assertEq(lp.creatorFees(address(t)) - cfBefore, share);
        assertEq(lp.holderPool(address(t)) - poolBefore, share);
        assertEq(platform.balance - platBefore, fee - 3 * share);
        (Vm.Log memory fd,) = _findLog(logs, KgiwaLaunchpad.FeesDistributed.selector);
        (uint256 p, uint256 c, uint256 h, uint256 b) = abi.decode(fd.data, (uint256, uint256, uint256, uint256));
        assertEq(p + c + h + b, fee);
        _assertLedger();
    }

    function test_OddFeeRoundingFourPartsSumExactly() public {
        uint256 v = 1_234_567_891_234_567; // fee not divisible by 5
        vm.recordLogs();
        _buy(alice, t, v);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (Vm.Log memory fd,) = _findLog(logs, KgiwaLaunchpad.FeesDistributed.selector);
        (uint256 p, uint256 c, uint256 h, uint256 b) = abi.decode(fd.data, (uint256, uint256, uint256, uint256));
        uint256 fee = v * 200 / 10_000;
        assertEq(p + c + h + b, fee);
        assertEq(c, fee * 20 / 100);
        assertEq(p, fee - 3 * (fee * 20 / 100), "platform takes rounding remainder");
        _assertLedger();
    }

    function test_CreatorClaimsOnceOnlyCreator() public {
        _buy(alice, t, 10 ether);
        uint256 owed = lp.creatorFees(address(t));
        assertEq(owed, 0.04 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NotCreator()"));
        lp.claimCreatorFees(address(t));

        uint256 b = creator.balance;
        vm.expectEmit(true, true, false, true, address(lp));
        emit KgiwaLaunchpad.CreatorFeesClaimed(address(t), creator, owed);
        vm.prank(creator);
        lp.claimCreatorFees(address(t));
        assertEq(creator.balance - b, owed);
        assertEq(lp.creatorFees(address(t)), 0);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("NothingToReceive()"));
        lp.claimCreatorFees(address(t));

        // accrues again
        _buy(bob, t, 1 ether);
        assertEq(lp.creatorFees(address(t)), 0.004 ether);
        _assertLedger();
    }

    function test_ContractBalanceLedgerAcrossManyOps() public {
        LaunchToken t2 = _create(300);
        _buy(alice, t, 3 ether);
        _buy(bob, t2, 2 ether);
        _assertLedger();
        _buy(carol, t, 20 ether);
        _sell(alice, t, t.balanceOf(alice) / 2);
        _sell(bob, t2, t2.balanceOf(bob));
        _assertLedger();
        vm.prank(creator);
        lp.claimCreatorFees(address(t));
        vm.prank(alice);
        lp.claimHolderRewards(address(t));
        _assertLedger();
        _assertLocked(t, 0);
        _assertLocked(t2, 0);
    }

    // ---- (7) burn accounting

    function test_BurnAdvancesCurveAndSupplyNeverRises() public {
        uint256 supply = t.totalSupply();
        uint256 inv = _info(t).inv;
        uint256 res = _info(t).reserve;
        for (uint256 i; i < 6; ++i) {
            uint256 sold0 = _sold(t);
            uint256 v = (i + 1) * 3 ether;
            uint256 got = _buy(alice, t, v);
            uint256 s2 = t.totalSupply();
            assertLt(s2, supply, "supply strictly drops on buy (burn)");
            uint256 burned = supply - s2;
            assertEq(inv - _info(t).inv, got + burned, "position advanced by tokens + burned");
            assertEq(_info(t).reserve - res, _net(v, 200) + v * 200 / 10_000 * 20 / 100);
            assertEq(_sold(t), sold0 + got + burned);
            supply = s2;
            inv = _info(t).inv;
            res = _info(t).reserve;
        }
        // sells burn too, supply still never rises
        uint256 amt = t.balanceOf(alice) / 2;
        _sell(alice, t, amt);
        assertLt(t.totalSupply(), supply);
    }

    function test_BurnClampsAtCurveEndAndStaysBacked() public {
        _fillCurve(alice, t);
        assertEq(_info(t).inv, 0);
        assertLt(t.totalSupply(), TOTAL);
        assertEq(t.balanceOf(address(lp)), LOCKED);
        assertEq(t.balanceOf(alice) + _burned(t), CURVE);
        _assertBacked(t);
        _assertLedger();
        // curve is exhausted: burns are no-ops, a sell still works and burn buys back in
        uint256 half = t.balanceOf(alice) / 2;
        _sell(alice, t, half);
        _assertBacked(t);
        _assertLocked(t, 0);
    }

    // ---- (9) fee limits & creation fees

    function test_InvalidFeeBpsReverts() public {
        uint256[4] memory bad = [uint256(0), 99, 301, 500];
        uint256 cf = lp.instantCreationFee();
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(creator);
            vm.expectRevert(abi.encodeWithSignature("InvalidFee()"));
            lp.createInstant{value: cf}("T", "T", "", TOTAL, bad[i]);
            vm.prank(creator);
            vm.expectRevert(abi.encodeWithSignature("InvalidFee()"));
            lp.createFundraise{value: 0.05 ether}("T", "T", "", TOTAL, 1 ether, bad[i]);
        }
    }

    function test_FeeBoundsAccepted() public {
        LaunchToken lo = _create(100);
        LaunchToken hi = _create(300);
        assertEq(_info(lo).bps, 100);
        assertEq(_info(hi).bps, 300);
        _buy(alice, hi, 1 ether);
        assertEq(lp.creatorFees(address(hi)), 1 ether * 300 / 10_000 * 20 / 100);
    }

    function test_InvalidSupplyAndMetadata() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidSupply()"));
        lp.createInstant{value: 1 ether}("T", "T", "", TOTAL - 1, 100);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidSupply()"));
        lp.createInstant{value: 1 ether}("T", "T", "", TOTAL + 1, 100);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidMetadata()"));
        lp.createInstant{value: 1 ether}("", "T", "", TOTAL, 100);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidMetadata()"));
        lp.createInstant{value: 1 ether}("T", "", "", TOTAL, 100);
    }

    function test_InstantCreationFeeAndFirstBuy() public {
        assertEq(lp.instantCreationFee(), 0.0001 ether);
        uint256 platBefore = platform.balance;
        vm.prank(creator);
        lp.createInstant{value: 0.0001 ether + 1 ether}("Tok", "TK", "uri", TOTAL, 100);
        LaunchToken n = LaunchToken(lp.tokenAt(lp.tokenCount() - 1));
        assertApproxEqAbs(n.balanceOf(creator), Ref.position(0, 0.99 ether), TOKEN_TOL, "first buy by creator");
        assertEq(platform.balance - platBefore, 0.0001 ether + 0.004 ether, "creation fee + platform share");
        assertEq(_info(n).volume, 1 ether);
        assertEq(lp.traderAt(0), creator);
        _assertLedger();
    }

    function test_InstantCreationNoRemainderNoBuy() public {
        LaunchToken n = _create(100);
        assertEq(n.balanceOf(creator), 0);
        assertEq(lp.traderCount(), 0);
        assertEq(_info(n).volume, 0);
        assertEq(_info(n).reserve, 0);
    }

    function test_InstantCreationPaymentReverts() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidPayment()"));
        lp.createInstant{value: 0.0001 ether - 1}("T", "T", "", TOTAL, 100);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("TradeTooSmall()"));
        lp.createInstant{value: 0.0001 ether + MIN_TRADE - 1}("T", "T", "", TOTAL, 100);
    }

    function test_FundraiseCreationFeeExactAndConfigurable() public {
        assertEq(lp.fundraiseCreationFee(), 0.05 ether);
        vm.startPrank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidPayment()"));
        lp.createFundraise{value: 0.05 ether - 1}("T", "T", "", TOTAL, 1 ether, 100);
        vm.expectRevert(abi.encodeWithSignature("InvalidPayment()"));
        lp.createFundraise{value: 0.05 ether + 1}("T", "T", "", TOTAL, 1 ether, 100);
        uint256 pb = platform.balance;
        lp.createFundraise{value: 0.05 ether}("T", "T", "", TOTAL, 1 ether, 100);
        vm.stopPrank();
        assertEq(platform.balance - pb, 0.05 ether);
        assertEq(address(lp).balance, 0, "creation fees forwarded");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        lp.setFundraiseCreationFee(1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        lp.setInstantCreationFee(1 ether);

        vm.prank(owner);
        lp.setFundraiseCreationFee(0.2 ether);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidPayment()"));
        lp.createFundraise{value: 0.05 ether}("T", "T", "", TOTAL, 1 ether, 100);
        vm.prank(creator);
        lp.createFundraise{value: 0.2 ether}("T", "T", "", TOTAL, 1 ether, 100);
        assertEq(lp.fundraiseCount(), 2);

        vm.prank(owner);
        lp.setInstantCreationFee(0.5 ether);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidPayment()"));
        lp.createInstant{value: 0.4 ether}("T", "T", "", TOTAL, 100);
        pb = platform.balance;
        vm.prank(creator);
        lp.createInstant{value: 0.5 ether}("T", "T", "", TOTAL, 100);
        assertEq(platform.balance - pb, 0.5 ether);
    }
}

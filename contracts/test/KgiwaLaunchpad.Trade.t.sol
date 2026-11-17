// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {KgiwaLaunchpadTestBase, Ref, TI} from "./KgiwaLaunchpad.Base.t.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";

contract KgiwaLaunchpadTradeTest is KgiwaLaunchpadTestBase {
    LaunchToken internal t;

    function setUp() public override {
        super.setUp();
        t = _create(100);
    }

    function _reserveSlot() internal view returns (bytes32) {
        // tokens mapping is storage slot 5; TokenInfo.reserveETH is struct field index 4.
        return bytes32(uint256(keccak256(abi.encode(address(t), uint256(5)))) + 4);
    }

    // ---- (2) reversibility

    function test_BuyThenSellAllMatchesFeeRules() public {
        uint256 v = 10 ether;
        uint256 got = _buy(alice, t, v);
        uint256 s1 = _sold(t); // includes fee-burn advance
        uint256 grossRef = Ref.reserve(s1) - Ref.reserve(s1 - got);
        (uint256 q, uint256 fee,) = lp.quoteSellDetail(address(t), got);
        assertApproxEqAbs(q + fee, grossRef, 2e3, "gross == R(s)-R(s-x)");
        assertEq(fee, (q + fee) * 100 / 10_000, "fee is exactly 1% of gross");
        uint256 out = _sell(alice, t, got);
        assertEq(out, q, "payout == quote");
        assertLt(out, v);
        assertGt(out, v * 97 / 100);
        // inventory returns except the burned portion (buy-burn and sell-burn)
        assertEq(_info(t).inv, CURVE - _burned(t), "inventory == C - burned");
        assertEq(t.balanceOf(alice), 0);
        _assertBacked(t);
        _assertLocked(t, 0);
    }

    function test_SellPartialLeavesRestHeld() public {
        uint256 got = _buy(alice, t, 5 ether);
        _sell(alice, t, got / 4);
        assertEq(t.balanceOf(alice), got - got / 4);
        _assertBacked(t);
        _assertLocked(t, 0);
    }

    // ---- (4) InsufficientReserve

    function test_SellRevertsInsufficientReserveWhenForcedShort() public {
        uint256 got = _buy(alice, t, 10 ether);
        (uint256 q, uint256 fee,) = lp.quoteSellDetail(address(t), got);
        uint256 gross = q + fee;
        vm.store(address(lp), _reserveSlot(), bytes32(gross - 1));
        assertEq(_info(t).reserve, gross - 1);
        vm.expectRevert(abi.encodeWithSignature("InsufficientReserve()"));
        lp.quoteSellDetail(address(t), got);
        vm.prank(alice);
        t.approve(address(lp), got);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientReserve()"));
        lp.sell(address(t), got, 0);
        // exactly the gross is enough
        vm.store(address(lp), _reserveSlot(), bytes32(gross));
        vm.prank(alice);
        lp.sell(address(t), got, 0);
        assertEq(t.balanceOf(alice), 0);
    }

    // ---- sell revert paths

    function test_SellRevertPaths() public {
        uint256 got = _buy(alice, t, 1 ether);
        vm.prank(alice);
        t.approve(address(lp), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("TradeTooSmall()"));
        lp.sell(address(t), 0, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NothingToReceive()"));
        lp.sell(address(t), 1, 0);

        // 20 tokens ~ 5e12 wei gross < MIN_TRADE
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("TradeTooSmall()"));
        lp.sell(address(t), 20e18, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientInventory()"));
        lp.sell(address(t), CURVE, 0);

        uint256 q = lp.quoteSell(address(t), got);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("SlippageExceeded()"));
        lp.sell(address(t), got, q + 1);

        // bob has no tokens
        vm.prank(bob);
        t.approve(address(lp), got);
        vm.prank(bob);
        vm.expectRevert();
        lp.sell(address(t), got, 0);
    }

    function test_BuySlippage() public {
        uint256 q = lp.quoteBuy(address(t), 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("SlippageExceeded()"));
        lp.buy{value: 1 ether}(address(t), q + 1);
        vm.prank(alice);
        lp.buy{value: 1 ether}(address(t), q);
        assertEq(t.balanceOf(alice), q);
    }

    // ---- (5) first buyer exits fully, later buyers too

    function test_FirstBuyerAndLaterBuyersAllExitInFull() public {
        address[3] memory who = [alice, bob, carol];
        uint256[3] memory spend = [uint256(20 ether), 30 ether, 40 ether];
        uint256[3] memory held;
        for (uint256 i; i < 3; ++i) {
            held[i] = _buy(who[i], t, spend[i]);
            _assertBacked(t);
        }
        uint256 paid;
        for (uint256 i; i < 3; ++i) {
            (uint256 q, uint256 fee,) = lp.quoteSellDetail(address(t), held[i]);
            uint256 resBefore = _info(t).reserve;
            uint256 platBefore = platform.balance;
            uint256 out = _sell(who[i], t, held[i]);
            assertEq(out, q, "exact payout");
            assertEq(t.balanceOf(who[i]), 0);
            uint256 burnShare = fee * 20 / 100;
            assertEq(_info(t).reserve, resBefore - (q + fee) + burnShare, "reserve accounting");
            // holders share is redirected to platform only for the last seller (circulating == 0)
            uint256 expPlat = fee - 3 * burnShare + (i == 2 ? burnShare : 0);
            assertEq(platform.balance - platBefore, expPlat, "platform share");
            _assertBacked(t);
            _assertLocked(t, 0);
            paid += out;
        }
        assertLt(paid, 90 ether);
        assertGt(paid, 85 ether);
        assertEq(t.totalSupply() - t.balanceOf(address(lp)), 0, "nobody left in circulation");
    }

    function test_AllHoldersClaimRewardsAfterFullExit() public {
        address[3] memory who = [alice, bob, carol];
        for (uint256 i; i < 3; ++i) _buy(who[i], t, 20 ether);
        for (uint256 i; i < 3; ++i) _sell(who[i], t, t.balanceOf(who[i]));
        uint256 pool = lp.holderPool(address(t));
        uint256 claimed;
        for (uint256 i; i < 3; ++i) {
            uint256 pend = lp.pendingHolderRewards(address(t), who[i]);
            if (pend == 0) continue;
            uint256 b = who[i].balance;
            vm.prank(who[i]);
            lp.claimHolderRewards(address(t));
            claimed += who[i].balance - b;
        }
        assertLe(claimed, pool);
        assertLe(pool - claimed, 10, "only dust left");
        assertEq(lp.holderPool(address(t)), pool - claimed);
    }

    // ---- (13) quotes match actual trades

    function test_QuoteBuyDetailMatchesActualTrade() public {
        uint256 v = 7 ether;
        (uint256 qOut, uint256 qFee, uint256 qPrice) = lp.quoteBuyDetail(address(t), v);
        assertEq(qOut, lp.quoteBuy(address(t), v));
        vm.recordLogs();
        uint256 got = _buy(alice, t, v);
        assertEq(got, qOut, "tokens");
        (Vm.Log memory log, bool found) = _lastLog(KgiwaLaunchpad.Trade.selector);
        assertTrue(found);
        (bool isBuy, uint256 eth, uint256 tok, uint256 fee, uint256 evPrice) =
            abi.decode(log.data, (bool, uint256, uint256, uint256, uint256));
        assertTrue(isBuy);
        assertEq(eth, v);
        assertEq(tok, qOut);
        assertEq(fee, qFee);
        assertEq(fee, v * 100 / 10_000);
        assertEq(evPrice, _info(t).price, "event carries final price");
        assertGe(evPrice, qPrice, "quote price excludes fee burn");
        assertApproxEqRel(qPrice, Ref.price(got), 1e9, "quote price == curve price at main position");
    }

    function test_QuoteSellDetailMatchesActualTrade() public {
        uint256 got = _buy(alice, t, 12 ether);
        uint256 amt = got / 3;
        uint256 sold0 = _sold(t);
        (uint256 qOut, uint256 qFee, uint256 qPrice) = lp.quoteSellDetail(address(t), amt);
        assertEq(qOut, lp.quoteSell(address(t), amt));
        assertApproxEqRel(qPrice, Ref.price(sold0 - amt), 1e9);
        vm.recordLogs();
        uint256 out = _sell(alice, t, amt);
        assertEq(out, qOut);
        (Vm.Log memory log, bool found) = _lastLog(KgiwaLaunchpad.Trade.selector);
        assertTrue(found);
        (bool isBuy, uint256 eth, uint256 tok, uint256 fee, uint256 evPrice) =
            abi.decode(log.data, (bool, uint256, uint256, uint256, uint256));
        assertFalse(isBuy);
        assertEq(eth, qOut + qFee, "event ethAmount is gross");
        assertEq(tok, amt);
        assertEq(fee, qFee);
        assertGe(evPrice, qPrice);
    }

    function test_QuoteSellRevertsBeyondSold() public {
        _buy(alice, t, 1 ether);
        vm.expectRevert(abi.encodeWithSignature("InsufficientInventory()"));
        lp.quoteSell(address(t), CURVE);
    }

    // ---- unique traders / volume

    function test_UniqueTradersAndVolume() public {
        assertEq(lp.traderCount(), 0);
        assertEq(lp.totalVolume(), 0);
        _buy(alice, t, 1 ether);
        _buy(alice, t, 2 ether);
        _buy(bob, t, 3 ether);
        assertEq(lp.traderCount(), 2);
        assertEq(lp.traderAt(0), alice);
        assertEq(lp.traderAt(1), bob);
        assertEq(lp.totalVolume(), 6 ether);
        assertEq(_info(t).volume, 6 ether);

        uint256 amt = t.balanceOf(bob);
        vm.prank(bob);
        t.approve(address(lp), amt);
        (uint256 q, uint256 fee,) = lp.quoteSellDetail(address(t), amt);
        vm.prank(bob);
        lp.sell(address(t), amt, 0);
        assertEq(lp.traderCount(), 2, "bob already a trader");
        assertEq(lp.totalVolume(), 6 ether + q + fee, "volume adds gross sell");

        // a seller who got tokens by transfer is a new trader
        vm.prank(alice);
        t.transfer(carol, 1000e18);
        _sell(carol, t, 1000e18);
        assertEq(lp.traderCount(), 3);
        assertEq(lp.traderAt(2), carol);
    }
}

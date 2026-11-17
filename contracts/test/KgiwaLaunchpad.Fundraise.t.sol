// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {KgiwaLaunchpadTestBase, Ref, TI} from "./KgiwaLaunchpad.Base.t.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";

contract KgiwaLaunchpadFundraiseTest is KgiwaLaunchpadTestBase {
    function _fr(uint256 target, uint256 bps) internal returns (uint256 id) {
        vm.prank(creator);
        lp.createFundraise{value: 0.05 ether}("FR", "FR", "uri", TOTAL, target, bps);
        id = lp.fundraiseCount() - 1;
    }

    function _contrib(address who, uint256 id, uint256 v) internal {
        vm.prank(who);
        lp.contribute{value: v}(id);
    }

    function _frState(uint256 id) internal view returns (uint256 raised, uint256 price, uint8 status, address token) {
        (,,,,,, raised, price,, status, token) = lp.fundraises(id);
    }

    function _alloc(uint256 id, address who) internal view returns (uint256 eth, uint256 tok, bool claimed, bool refunded) {
        return lp.fundraiseContribution(id, who);
    }

    // ---- targets

    function test_TargetBoundaries() public {
        _fr(0.01 ether, 100);
        _fr(50 ether, 100);
        _fr(25 ether, 300);
        assertEq(lp.fundraiseCount(), 3);
        uint256[4] memory bad = [uint256(0), 0.00999 ether, 50.0001 ether, 1000 ether];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(creator);
            vm.expectRevert(abi.encodeWithSignature("InvalidTarget()"));
            lp.createFundraise{value: 0.05 ether}("FR", "FR", "", TOTAL, bad[i], 100);
        }
    }

    function test_CreationStoresMetadataAndDeadline() public {
        vm.expectEmit(true, true, false, true, address(lp));
        emit KgiwaLaunchpad.FundraiseCreated(0, creator, 2 ether);
        uint256 id = _fr(2 ether, 150);
        (address cr,,,, uint256 supply, uint256 target, uint256 raised, uint256 price, uint256 bps, uint8 status, address tok) =
            lp.fundraises(id);
        assertEq(cr, creator);
        assertEq(supply, TOTAL);
        assertEq(target, 2 ether);
        assertEq(raised, 0);
        assertEq(price, P0);
        assertEq(bps, 150);
        assertEq(status, 0);
        assertEq(tok, address(0));
        assertEq(lp.fundraiseDeadline(id), block.timestamp + 30 days);
        vm.expectRevert(abi.encodeWithSignature("InvalidFundraise()"));
        lp.fundraises(1);
    }

    // ---- contributions along the curve

    function test_ContributionsAllocateAlongCurve() public {
        uint256 id = _fr(10 ether, 100);
        vm.expectEmit(true, true, false, true, address(lp));
        emit KgiwaLaunchpad.Contribution(id, alice, 4 ether);
        _contrib(alice, id, 4 ether);
        (uint256 e1, uint256 t1,,) = _alloc(id, alice);
        assertEq(e1, 4 ether);
        assertApproxEqAbs(t1, Ref.position(0, 4 ether), TOKEN_TOL);
        (uint256 raised, uint256 price,,) = _frState(id);
        assertEq(raised, 4 ether);
        assertApproxEqRel(price, Ref.price(t1), 1e9);

        _contrib(bob, id, 3 ether);
        (, uint256 t2,,) = _alloc(id, bob);
        assertApproxEqAbs(t1 + t2, Ref.position(0, 7 ether), TOKEN_TOL, "same curve regardless of order");
        assertLt(t2, t1, "later contributors get fewer tokens per ETH");

        _contrib(alice, id, 1 ether); // cumulative allocation
        (uint256 e3, uint256 t3,,) = _alloc(id, alice);
        assertEq(e3, 5 ether);
        assertGt(t3, t1);
        assertEq(address(lp).balance, 8 ether);
        _assertLedger();
    }

    function test_ContributeRevertPaths() public {
        uint256 id = _fr(1 ether, 100);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("TradeTooSmall()"));
        lp.contribute{value: MIN_TRADE - 1}(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidFundraise()"));
        lp.contribute{value: 1 ether}(99);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidFundraise()"));
        lp.claim(99);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidFundraise()"));
        lp.refund(99);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidFundraise()"));
        lp.cancelFundraise(99);
    }

    // ---- fill: over-contribution, launch price continuity, backing

    function _fill1Eth() internal returns (uint256 id, LaunchToken ft, uint256 carolBefore) {
        id = _fr(1 ether, 100);
        _contrib(alice, id, 0.5 ether);
        _contrib(bob, id, 0.2 ether);
        carolBefore = carol.balance;
        vm.recordLogs();
        _contrib(carol, id, 5 ether); // only 0.3 accepted
        (,,, address tok) = _frState(id);
        ft = LaunchToken(tok);
    }

    function test_FillCapsOverContributionAndRefundsExcess() public {
        (uint256 id, LaunchToken ft, uint256 carolBefore) = _fill1Eth();
        assertEq(carolBefore - carol.balance, 0.3 ether, "excess refunded, only 0.3 spent");
        (uint256 ce,,,) = _alloc(id, carol);
        assertEq(ce, 0.3 ether);
        (uint256 raised,, uint8 status, address tok) = _frState(id);
        assertEq(raised, 1 ether);
        assertEq(status, 1);
        assertTrue(tok != address(0));
        assertEq(lp.tokenAt(lp.tokenCount() - 1), tok);

        bool launched;
        bool completed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == KgiwaLaunchpad.TokenLaunched.selector) launched = true;
            if (logs[i].topics[0] == KgiwaLaunchpad.FundraiseCompleted.selector) completed = true;
            if (logs[i].topics[0] == KgiwaLaunchpad.Contribution.selector) {
                assertEq(abi.decode(logs[i].data, (uint256)), 0.3 ether, "event reports accepted amount");
            }
        }
        assertTrue(launched && completed);

        TI memory ti = _info(ft);
        assertEq(ti.creator, creator);
        assertEq(ti.reserve, 1 ether, "reserveETH == raised");
        assertEq(ti.bps, 100);
        assertEq(ti.supply, TOTAL);
        assertEq(ti.volume, 1 ether);
        assertEq(lp.totalVolume(), 1 ether);
        assertEq(ft.totalSupply(), TOTAL);
        assertEq(ft.balanceOf(address(lp)), TOTAL);
        assertEq(address(lp).balance, 1 ether);
        assertGe(ti.reserve, lp.reserveRequired(address(ft)));
        _assertLedger();

        (, uint256 ta,,) = _alloc(id, alice);
        (, uint256 tb,,) = _alloc(id, bob);
        (, uint256 tc,,) = _alloc(id, carol);
        assertEq(CURVE - ti.inv, ta + tb + tc, "inventory reduced by exactly the allocations");
        assertApproxEqAbs(ta + tb + tc, Ref.position(0, 1 ether), TOKEN_TOL);
        _assertLocked(ft, ta + tb + tc);
    }

    function test_LaunchPriceContinuity() public {
        (uint256 id, LaunchToken ft,) = _fill1Eth();
        (, uint256 frPrice,,) = _frState(id);
        TI memory ti = _info(ft);
        assertEq(ti.price, frPrice, "token price == fundraise price at fill");
        uint256 sold = CURVE - ti.inv;
        assertApproxEqRel(ti.price, Ref.price(sold), 1e9, "marginal price at f.sold");
        assertGt(ti.price, P0);
        // the first market buy continues on the same curve
        (uint256 q,, uint256 np) = lp.quoteBuyDetail(address(ft), 1 ether);
        assertApproxEqAbs(sold + q, Ref.position(0, 1 ether + 0.99 ether), TOKEN_TOL, "no price jump at launch");
        assertGt(np, ti.price);
    }

    function test_ClaimOnce() public {
        (uint256 id, LaunchToken ft,) = _fill1Eth();
        (, uint256 ta,,) = _alloc(id, alice);
        vm.expectEmit(true, true, false, true, address(lp));
        emit KgiwaLaunchpad.Claimed(id, alice, ta);
        vm.prank(alice);
        lp.claim(id);
        assertEq(ft.balanceOf(alice), ta);
        (,, bool claimed,) = _alloc(id, alice);
        assertTrue(claimed);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("AlreadyProcessed()"));
        lp.claim(id);
        vm.prank(dave);
        vm.expectRevert(abi.encodeWithSignature("NothingToReceive()"));
        lp.claim(id);
        assertEq(ft.balanceOf(alice), ta, "no double payout");

        (, uint256 tb,,) = _alloc(id, bob);
        (, uint256 tc,,) = _alloc(id, carol);
        _assertLocked(ft, tb + tc);
        vm.prank(bob);
        lp.claim(id);
        vm.prank(carol);
        lp.claim(id);
        _assertLocked(ft, 0);
        // a claimer can sell back into the reserve, fully paid
        uint256 got = _sell(alice, ft, ta);
        assertGt(got, 0);
        _assertBacked(ft);
        _assertLedger();
    }

    function test_ClaimBeforeFillReverts() public {
        uint256 id = _fr(1 ether, 100);
        _contrib(alice, id, 0.5 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus()"));
        lp.claim(id);
    }

    function test_ContributeAfterFillReverts() public {
        (uint256 id,,) = _fill1Eth();
        vm.prank(dave);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus()"));
        lp.contribute{value: 1 ether}(id);
    }

    function test_CapacityTargetsFillAndAreBacked() public {
        uint256 lo = _fr(0.01 ether, 100);
        _contrib(alice, lo, 0.01 ether);
        (, , uint8 s1, address t1) = _frState(lo);
        assertEq(s1, 1);
        assertEq(_info(LaunchToken(t1)).reserve, 0.01 ether);
        _assertBacked(LaunchToken(t1));

        uint256 hi = _fr(50 ether, 100);
        _contrib(bob, hi, 30 ether);
        _contrib(carol, hi, 40 ether);
        (uint256 raised,, uint8 s2, address t2) = _frState(hi);
        assertEq(s2, 1);
        assertEq(raised, 50 ether);
        assertEq(_info(LaunchToken(t2)).reserve, 50 ether);
        _assertBacked(LaunchToken(t2));
        assertApproxEqAbs(CURVE - _info(LaunchToken(t2)).inv, Ref.position(0, 50 ether), TOKEN_TOL);
        _assertLedger();
    }

    // ---- cancel & refund

    function test_CancelOnlyCreatorWhileActive() public {
        uint256 id = _fr(1 ether, 100);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NotCreator()"));
        lp.cancelFundraise(id);

        vm.expectEmit(true, false, false, true, address(lp));
        emit KgiwaLaunchpad.FundraiseCancelled(id);
        vm.prank(creator);
        lp.cancelFundraise(id);
        (,, uint8 st,) = _frState(id);
        assertEq(st, 2);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus()"));
        lp.cancelFundraise(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus()"));
        lp.contribute{value: 1 ether}(id);

        (uint256 id2,,) = _fill1Eth();
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus()"));
        lp.cancelFundraise(id2);
    }

    function test_RefundExactContributionsOnce() public {
        uint256 id = _fr(10 ether, 100);
        _contrib(alice, id, 1.234 ether);
        _contrib(bob, id, 0.77 ether);
        _contrib(alice, id, 0.1 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus()"));
        lp.refund(id); // active, not expired

        vm.prank(creator);
        lp.cancelFundraise(id);
        vm.expectEmit(true, true, false, true, address(lp));
        emit KgiwaLaunchpad.Refunded(id, alice, 1.334 ether);
        assertEq(_refund(alice, id), 1.334 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("AlreadyProcessed()"));
        lp.refund(id);
        vm.prank(dave);
        vm.expectRevert(abi.encodeWithSignature("NothingToReceive()"));
        lp.refund(id);
        _assertLedger();
        assertEq(_refund(bob, id), 0.77 ether);
        assertEq(address(lp).balance, 0);
        _assertLedger();
    }

    function test_RefundAfterFillReverts() public {
        (uint256 id,,) = _fill1Eth();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus()"));
        lp.refund(id);
    }

    // ---- expiry

    function test_ExpiryBlocksContributionsAndAllowsRefundWithoutCancel() public {
        uint256 id = _fr(10 ether, 100);
        _contrib(alice, id, 2 ether);
        uint256 dl = lp.fundraiseDeadline(id);
        assertEq(dl, block.timestamp + 30 days);

        vm.warp(dl); // boundary: still active
        _contrib(bob, id, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus()"));
        lp.refund(id);

        vm.warp(dl + 1);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSignature("FundraiseExpired()"));
        lp.contribute{value: 1 ether}(id);
        assertEq(_refund(alice, id), 2 ether);
        assertEq(_refund(bob, id), 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("AlreadyProcessed()"));
        lp.refund(id);
        assertEq(address(lp).balance, 0);
        _assertLedger();
        // creator may still cancel an expired-but-active raise (status 0) without harming refunds
        vm.prank(creator);
        lp.cancelFundraise(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("AlreadyProcessed()"));
        lp.refund(id);
    }
}

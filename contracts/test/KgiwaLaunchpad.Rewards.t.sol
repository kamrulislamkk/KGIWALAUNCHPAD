// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {KgiwaLaunchpadTestBase, Ref, TI} from "./KgiwaLaunchpad.Base.t.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";

contract KgiwaLaunchpadRewardsTest is KgiwaLaunchpadTestBase {
    LaunchToken internal t;

    function setUp() public override {
        super.setUp();
        t = _create(100);
    }

    function _pend(address who) internal view returns (uint256) {
        return lp.pendingHolderRewards(address(t), who);
    }

    function _claim(address who) internal returns (uint256 got) {
        uint256 b = who.balance;
        vm.prank(who);
        lp.claimHolderRewards(address(t));
        got = who.balance - b;
    }

    function test_SoleHolderEarnsFullHolderShareAndClaimsOnce() public {
        _buy(alice, t, 10 ether); // fee 0.1 ETH => holders 0.02 ETH
        uint256 pool = lp.holderPool(address(t));
        assertEq(pool, 0.02 ether);
        uint256 p = _pend(alice);
        assertLe(p, pool);
        assertGe(p, pool - 2, "sole circulating holder earns the whole share");

        uint256 poolBefore = lp.holderPool(address(t));
        vm.expectEmit(true, true, false, true, address(lp));
        emit KgiwaLaunchpad.HolderRewardsClaimed(address(t), alice, p);
        assertEq(_claim(alice), p);
        assertEq(lp.holderPool(address(t)), poolBefore - p);
        assertEq(_pend(alice), 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NothingToReceive()"));
        lp.claimHolderRewards(address(t));
        _assertLedger();
    }

    function test_LaunchpadHoldingsAndBurnedTokensEarnNothing() public {
        _buy(alice, t, 10 ether);
        _buy(bob, t, 20 ether);
        _buy(carol, t, 5 ether);
        // everything not held by users (locked, inventory, burned) is outside the reward base
        assertEq(t.circulating(), t.balanceOf(alice) + t.balanceOf(bob) + t.balanceOf(carol));
        assertGt(_burned(t), 0);
        assertEq(_pend(address(lp)), 0, "launchpad has no entitlement");

        uint256 sum = _pend(alice) + _pend(bob) + _pend(carol);
        uint256 pool = lp.holderPool(address(t));
        assertLe(sum, pool, "entitlements never exceed pool");
        assertLe(pool - sum, 6, "no share leaks to launchpad / burned tokens");
    }

    function test_LaunchpadCannotClaimRewards() public {
        _buy(alice, t, 10 ether);
        vm.prank(address(lp));
        vm.expectRevert(abi.encodeWithSignature("NothingToReceive()"));
        lp.claimHolderRewards(address(t));
    }

    function test_NewHolderEarnsNothingFromPastDistributions() public {
        _buy(alice, t, 10 ether);
        uint256 aliceBefore = _pend(alice);
        uint256 half = t.balanceOf(alice) / 2;
        vm.prank(alice);
        t.transfer(dave, half);
        assertEq(_pend(dave), 0, "recipient of a transfer has no past rewards");
        assertEq(_pend(alice), aliceBefore, "sender keeps earned rewards");
        vm.prank(dave);
        vm.expectRevert(abi.encodeWithSignature("NothingToReceive()"));
        lp.claimHolderRewards(address(t));

        // a fresh buyer only participates in distributions from their own trade onwards
        uint256 pool0 = lp.holderPool(address(t));
        _buy(bob, t, 10 ether);
        uint256 share = lp.holderPool(address(t)) - pool0;
        uint256 bobPend = _pend(bob);
        assertLe(bobPend, share);
        assertApproxEqRel(bobPend, share * t.balanceOf(bob) / t.circulating(), 1e12);
        assertLt(bobPend, share, "bob did not capture alice's earlier rewards");
        // past + new distribution never exceed pool
        assertLe(_pend(alice) + _pend(bob) + _pend(dave), lp.holderPool(address(t)));
    }

    function test_TransfersPreserveEarnedRewards() public {
        _buy(alice, t, 10 ether);
        uint256 p = _pend(alice);
        assertGt(p, 0);
        uint256 all = t.balanceOf(alice);
        vm.prank(alice);
        t.transfer(bob, all);
        assertEq(t.balanceOf(alice), 0);
        assertEq(_pend(alice), p, "earned rewards stay with the sender");
        assertEq(_pend(bob), 0);
        assertEq(_claim(alice), p);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NothingToReceive()"));
        lp.claimHolderRewards(address(t));
        // bob now earns from later distributions only
        _buy(carol, t, 10 ether);
        assertGt(_pend(bob), 0);
        assertEq(_pend(alice), 0);
    }

    function test_SellKeepsEarnedRewards() public {
        _buy(alice, t, 10 ether);
        _buy(bob, t, 10 ether);
        uint256 p = _pend(alice);
        _sell(alice, t, t.balanceOf(alice));
        assertGe(_pend(alice), p, "rewards earned before exit are retained (plus own sell-fee share)");
        _assertBacked(t);
        assertGt(_claim(alice), 0);
    }

    function test_HolderShareRedirectedToPlatformWhenCirculatingBelowMin() public {
        uint256 platBefore = platform.balance;
        vm.recordLogs();
        vm.prank(creator);
        lp.buy{value: 1e14}(address(t), 0); // ~400 tokens < 1000e18
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertLt(t.circulating(), 1_000e18);
        uint256 fee = 1e14 * 100 / 10_000;
        uint256 share = fee * 20 / 100;
        assertEq(lp.holderPool(address(t)), 0, "nothing to pool");
        assertEq(lp.creatorFees(address(t)), share);
        assertEq(platform.balance - platBefore, fee - 2 * share, "platform gets platform + holders share");
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == KgiwaLaunchpad.FeesDistributed.selector) {
                (uint256 p, uint256 c, uint256 h, uint256 b) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
                assertEq(h, 0);
                assertEq(p, fee - 2 * share);
                assertEq(c, share);
                assertEq(p + c + h + b, fee);
                seen = true;
            }
        }
        assertTrue(seen);
        assertEq(_pend(creator), 0);
        _assertLedger();
    }

    function test_NearTotalExitThenLargeBuyTransferClaimDoesNotOverflow() public {
        _buy(alice, t, 5 ether);
        _buy(bob, t, 5 ether);
        // everyone but 5 tokens exits -> circulating far below 1000 tokens
        _sell(bob, t, t.balanceOf(bob));
        _sell(alice, t, t.balanceOf(alice) - 5e18);
        assertEq(t.circulating(), 5e18);
        uint256 pool = lp.holderPool(address(t));

        // trades while circulating is tiny redirect the holders share (no addRewards revert)
        _buy(carol, t, MIN_TRADE);
        // large buy flips circulating above the minimum again
        _buy(dave, t, 50 ether);
        assertGt(t.circulating(), 1_000e18);
        assertGt(lp.holderPool(address(t)), pool);

        // transfer / claim paths stay healthy
        vm.prank(alice);
        t.transfer(carol, 1e18);
        vm.prank(carol);
        t.transfer(alice, 1e18);
        uint256 pa = _pend(alice);
        if (pa > 0) assertEq(_claim(alice), pa);
        assertLe(_pend(alice) + _pend(bob) + _pend(carol) + _pend(dave), lp.holderPool(address(t)));

        // full exit to zero circulation, then rebuild from nothing
        uint256 aBal = t.balanceOf(alice);
        vm.prank(alice);
        t.transfer(dave, aBal);
        uint256 cBal = t.balanceOf(carol);
        vm.prank(carol);
        t.transfer(dave, cBal);
        _sell(dave, t, t.balanceOf(dave));
        assertEq(t.circulating(), 0);
        _buy(bob, t, MIN_TRADE);
        _buy(bob, t, 100 ether);
        _assertBacked(t);
        _assertLedger();
        _assertLocked(t, 0);
    }

    function test_ClaimedTotalNeverExceedsHolderPool() public {
        address[4] memory who = [alice, bob, carol, dave];
        for (uint256 r; r < 3; ++r) {
            for (uint256 i; i < 4; ++i) _buy(who[i], t, (i + 1) * (r + 1) * 1 ether);
            uint256 third = t.balanceOf(alice) / 3;
            vm.prank(alice);
            t.transfer(dave, third);
            _sell(bob, t, t.balanceOf(bob) / 2);
        }
        uint256 pool = lp.holderPool(address(t));
        uint256 claimed;
        for (uint256 i; i < 4; ++i) {
            if (_pend(who[i]) > 0) claimed += _claim(who[i]);
        }
        assertLe(claimed, pool);
        assertEq(lp.holderPool(address(t)), pool - claimed);
        assertLe(lp.holderPool(address(t)), 20, "only rounding dust remains");
        _assertLedger();
    }

    // ---- unclaimed fundraise allocations earn nothing

    function test_UnclaimedFundraiseAllocationsEarnNothing() public {
        vm.prank(creator);
        lp.createFundraise{value: 0.05 ether}("FR", "FR", "", TOTAL, 1 ether, 100);
        vm.prank(alice);
        lp.contribute{value: 0.6 ether}(0);
        vm.prank(bob);
        lp.contribute{value: 0.4 ether}(0);
        LaunchToken ft = LaunchToken(lp.tokenAt(lp.tokenCount() - 1));
        assertEq(ft.circulating(), 0, "all allocations still in launchpad");

        vm.prank(carol);
        lp.buy{value: 10 ether}(address(ft), 0);
        uint256 pool = lp.holderPool(address(ft));
        assertEq(pool, 0.02 ether);
        assertEq(lp.pendingHolderRewards(address(ft), alice), 0, "unclaimed allocation earns nothing");
        assertEq(lp.pendingHolderRewards(address(ft), bob), 0);
        assertGe(lp.pendingHolderRewards(address(ft), carol), pool - 2, "carol earns the entire share");

        // claiming later does not retroactively earn
        vm.prank(alice);
        lp.claim(0);
        assertEq(lp.pendingHolderRewards(address(ft), alice), 0, "claimed allocation: no past rewards");
        vm.prank(carol);
        lp.buy{value: 1 ether}(address(ft), 0);
        assertGt(lp.pendingHolderRewards(address(ft), alice), 0, "now earns from new distributions");
        assertEq(lp.pendingHolderRewards(address(ft), bob), 0, "bob still unclaimed");
        uint256 sum = lp.pendingHolderRewards(address(ft), alice) + lp.pendingHolderRewards(address(ft), carol);
        assertLe(sum, lp.holderPool(address(ft)));
    }
}

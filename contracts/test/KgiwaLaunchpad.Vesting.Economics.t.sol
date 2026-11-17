// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {KgiwaLaunchpadTestBase, TI} from "./KgiwaLaunchpad.Base.t.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";

/// @dev v2.2 vesting: refund paths, schedule start, ledger/reserve/supply invariants, rewards, sell-back.
contract KgiwaLaunchpadVestingEconomicsTest is KgiwaLaunchpadTestBase {
    uint256 internal constant FEE = 0.05 ether;
    bytes4 internal constant NOTHING = bytes4(keccak256("NothingToReceive()"));
    bytes4 internal constant STATUS = bytes4(keccak256("InvalidStatus()"));

    function _frV(uint256 target, uint256 vh) internal returns (uint256 id) {
        vm.prank(creator);
        lp.createFundraiseVested{value: FEE}("FR", "FR", "uri", TOTAL, target, 100, vh);
        id = lp.fundraiseCount() - 1;
    }

    function _contrib(address who, uint256 id, uint256 v) internal {
        vm.prank(who);
        lp.contribute{value: v}(id);
    }

    function _tok(uint256 id) internal view returns (LaunchToken) {
        (,,,,,,,,,, address t) = lp.fundraises(id);
        return LaunchToken(t);
    }

    function _alloc(uint256 id, address who) internal view returns (uint256 t) {
        (, t,,) = lp.fundraiseContribution(id, who);
    }

    function _fill(uint256 vh) internal returns (uint256 id, LaunchToken ft) {
        id = _frV(1 ether, vh);
        _contrib(alice, id, 0.5 ether);
        _contrib(bob, id, 0.3 ether);
        _contrib(carol, id, 0.2 ether);
        ft = _tok(id);
    }

    function _claim(address who, uint256 id) internal returns (uint256 got) {
        LaunchToken ft = _tok(id);
        uint256 b = ft.balanceOf(who);
        vm.prank(who);
        lp.claim(id);
        got = ft.balanceOf(who) - b;
    }

    // ---------------------------------------------------------------- cancel / refund / expiry

    function test_CancelAndRefundUnaffectedByVesting() public {
        uint256 id = _frV(10 ether, 48);
        _contrib(alice, id, 1.234 ether);
        _contrib(bob, id, 0.77 ether);
        _contrib(alice, id, 0.1 ether);
        vm.prank(alice);
        vm.expectRevert(STATUS);
        lp.refund(id); // active, not expired
        vm.prank(creator);
        lp.cancelFundraise(id);
        (uint256 vh, uint256 lt) = lp.fundraiseVesting(id);
        assertEq(vh, 48);
        assertEq(lt, 0, "never launched");
        vm.expectEmit(true, true, false, true, address(lp));
        emit KgiwaLaunchpad.Refunded(id, alice, 1.334 ether);
        assertEq(_refund(alice, id), 1.334 ether);
        vm.prank(alice);
        vm.expectRevert(KgiwaLaunchpad.AlreadyProcessed.selector);
        lp.refund(id);
        assertEq(_refund(bob, id), 0.77 ether);
        assertEq(address(lp).balance, 0);
        // no claim path on a cancelled vested raise
        assertEq(lp.claimableOf(id, alice), 0);
        vm.prank(alice);
        vm.expectRevert(STATUS);
        lp.claim(id);
        _assertLedger();
    }

    function test_ExpiryRefundUnaffectedByVesting() public {
        uint256 id = _frV(10 ether, 24);
        _contrib(alice, id, 2 ether);
        _contrib(bob, id, 1 ether);
        vm.warp(lp.fundraiseDeadline(id) + 1);
        vm.prank(carol);
        vm.expectRevert(KgiwaLaunchpad.FundraiseExpired.selector);
        lp.contribute{value: 1 ether}(id);
        vm.prank(alice);
        vm.expectRevert(STATUS);
        lp.claim(id);
        assertEq(lp.claimableOf(id, alice), 0);
        assertEq(_refund(alice, id), 2 ether);
        assertEq(_refund(bob, id), 1 ether);
        assertEq(address(lp).balance, 0);
        _assertLedger();
    }

    function test_RefundWhilePausedOnVestedRaise() public {
        uint256 id = _frV(10 ether, 24);
        _contrib(alice, id, 2 ether);
        vm.prank(creator);
        lp.cancelFundraise(id);
        vm.prank(owner);
        lp.setPaused(true);
        assertEq(_refund(alice, id), 2 ether);
    }

    function test_RefundAfterVestedFillReverts() public {
        (uint256 id,) = _fill(24);
        vm.prank(alice);
        vm.expectRevert(STATUS);
        lp.refund(id);
    }

    // ---------------------------------------------------------------- schedule starts at fill

    function test_VestingUnaffectedByWhenContributorsContributed() public {
        uint256 id = _frV(1 ether, 24);
        _contrib(alice, id, 0.5 ether);
        skip(10 days);
        _contrib(bob, id, 0.3 ether);
        skip(10 days);
        _contrib(carol, id, 0.2 ether); // fills here
        uint256 fillTime = block.timestamp;
        (, uint256 lt) = lp.fundraiseVesting(id);
        assertEq(lt, fillTime, "launchTime == fill block, not first contribution");
        uint256 a = _alloc(id, alice);
        uint256 c = _alloc(id, carol);
        // alice contributed 20 days ago, carol just now: both identical at fill
        assertEq(lp.claimableOf(id, alice), 0);
        assertEq(lp.claimableOf(id, carol), 0);
        vm.prank(alice);
        vm.expectRevert(NOTHING);
        lp.claim(id);
        skip(1 hours);
        assertEq(lp.claimableOf(id, alice), a / 24);
        assertEq(lp.claimableOf(id, carol), c / 24);
        skip(23 hours);
        assertEq(lp.claimableOf(id, alice), a);
        assertEq(lp.claimableOf(id, carol), c);
    }

    function test_LaunchTimeIsSetByTheFillingCallOnly() public {
        uint256 id = _frV(1 ether, 48);
        _contrib(alice, id, 0.5 ether);
        (, uint256 lt) = lp.fundraiseVesting(id);
        assertEq(lt, 0);
        skip(3 days);
        _contrib(bob, id, 5 ether); // over-contribution fills; excess refunded
        (, lt) = lp.fundraiseVesting(id);
        assertEq(lt, block.timestamp);
        skip(1 days);
        assertEq(lp.claimableOf(id, bob), _alloc(id, bob) / 2);
    }

    // ---------------------------------------------------------------- invariants through a schedule

    function test_InvariantsHoldAtEveryStepOfVestedSchedule() public {
        (uint256 id, LaunchToken ft) = _fill(48);
        uint256 t0 = block.timestamp;
        address[3] memory u = [alice, bob, carol];
        uint256 total = _alloc(id, alice) + _alloc(id, bob) + _alloc(id, carol);
        uint256 claimed;
        uint256 lastSupply = ft.totalSupply();
        for (uint256 s; s <= 104; ++s) {
            vm.warp(t0 + s * 30 minutes);
            // some market activity so fees burn inventory while allocations are still unclaimed
            if (s % 8 == 3) _buy(dave, ft, 0.05 ether);
            if (s % 20 == 11 && ft.balanceOf(dave) > 0) _sell(dave, ft, ft.balanceOf(dave) / 3);
            uint256 c = lp.claimableOf(id, u[s % 3]);
            if (c != 0) {
                uint256 got = _claim(u[s % 3], id);
                assertEq(got, c);
                claimed += got;
            }
            _assertLocked(ft, total - claimed);
            _assertBacked(ft);
            _assertLedger();
            assertLe(ft.totalSupply(), lastSupply, "supply never rises");
            lastSupply = ft.totalSupply();
            assertEq(ft.circulating(), ft.totalSupply() - ft.balanceOf(address(lp)));
        }
        for (uint256 j; j < 3; ++j) if (lp.claimableOf(id, u[j]) != 0) claimed += _claim(u[j], id);
        assertEq(claimed, total, "all allocations released exactly");
        _assertLocked(ft, 0);
    }

    // ---------------------------------------------------------------- holder rewards exclude unclaimed

    function test_HolderRewardsExcludeLaunchpadHeldUnclaimed() public {
        (uint256 id, LaunchToken ft) = _fill(24);
        assertEq(ft.circulating(), 0, "unclaimed allocations are not circulating");
        assertEq(lp.pendingHolderRewards(address(ft), alice), 0);

        _buy(dave, ft, 1 ether); // fee 0.01 ETH, holders 20% = 0.002 ETH
        uint256 pool1 = lp.holderPool(address(ft));
        assertEq(pool1, 0.002 ether);
        assertEq(ft.circulating(), ft.balanceOf(dave));
        assertApproxEqAbs(lp.pendingHolderRewards(address(ft), dave), pool1, 2, "all rewards to the only circulating holder");
        assertEq(lp.pendingHolderRewards(address(ft), alice), 0, "unclaimed allocation earns nothing");
        assertEq(lp.pendingHolderRewards(address(ft), address(lp)), 0);
        uint256 daveP1 = lp.pendingHolderRewards(address(ft), dave);

        skip(12 hours);
        _claim(alice, id);
        assertEq(lp.pendingHolderRewards(address(ft), alice), 0, "no retroactive rewards on claim");
        assertEq(lp.pendingHolderRewards(address(ft), dave), daveP1);

        _buy(dave, ft, 1 ether);
        uint256 pool2 = lp.holderPool(address(ft)) - pool1;
        uint256 aBal = ft.balanceOf(alice);
        uint256 dBal = ft.balanceOf(dave);
        uint256 pa = lp.pendingHolderRewards(address(ft), alice);
        assertApproxEqAbs(pa, pool2 * aBal / (aBal + dBal), 10, "alice share only of post-claim rewards");
        uint256 pd = lp.pendingHolderRewards(address(ft), dave);
        assertLe(pa + pd, lp.holderPool(address(ft)));
        assertApproxEqAbs(pa + pd, lp.holderPool(address(ft)), 10, "pool fully attributed to circulating holders");
        // bob/carol never claimed: still nothing
        assertEq(lp.pendingHolderRewards(address(ft), bob), 0);
        assertEq(lp.pendingHolderRewards(address(ft), carol), 0);
    }

    // ---------------------------------------------------------------- selling early-claimed tokens

    function test_EarlyClaimedTokensCanBeSoldBackAndVestingContinues() public {
        (uint256 id, LaunchToken ft) = _fill(24);
        uint256 a = _alloc(id, alice);
        skip(6 hours);
        uint256 early = _claim(alice, id);
        assertEq(early, a * 6 / 24);

        TI memory before_ = _info(ft);
        (uint256 q, uint256 fee,) = lp.quoteSellDetail(address(ft), early);
        uint256 got = _sell(alice, ft, early);
        assertEq(got, q, "payout equals quote");
        assertGt(got, 0);
        TI memory after_ = _info(ft);
        // gross leaves the reserve; the 20% burn share of the fee is re-added by the fee-funded burn buy
        assertEq(before_.reserve - after_.reserve, q + fee - fee * 20 / 100, "reserve debited by gross payout");
        assertGt(after_.inv, before_.inv, "sold tokens return to curve inventory");
        assertGe(after_.reserve, lp.reserveRequired(address(ft)), "still fully backed");
        uint256 unclaimed = _alloc(id, alice) - early + _alloc(id, bob) + _alloc(id, carol);
        _assertLocked(ft, unclaimed);
        _assertLedger();

        // schedule is unaffected by the sale: remaining vests, total released == allocation
        skip(18 hours);
        uint256 rest = _claim(alice, id);
        assertEq(early + rest, a);
        assertEq(ft.balanceOf(alice), rest, "sold the early tranche, holds the rest");
        (,, bool claimed,) = lp.fundraiseContribution(id, alice);
        assertTrue(claimed);
        _assertLocked(ft, _alloc(id, bob) + _alloc(id, carol));
        // the later tranche can also be sold into the reserve
        uint256 got2 = _sell(alice, ft, rest);
        assertGt(got2, 0);
        _assertBacked(ft);
        _assertLedger();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {KgiwaLaunchpadTestBase, TI} from "./KgiwaLaunchpad.Base.t.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";

/// @dev v2.2 fundraise vesting: instant / 24h / 48h discrete hourly release starting at fill.
contract KgiwaLaunchpadVestingTest is KgiwaLaunchpadTestBase {
    uint256 internal constant FEE = 0.05 ether;
    bytes4 internal constant NOTHING = bytes4(keccak256("NothingToReceive()"));
    bytes4 internal constant PROCESSED = bytes4(keccak256("AlreadyProcessed()"));
    bytes4 internal constant STATUS = bytes4(keccak256("InvalidStatus()"));

    // ---------------------------------------------------------------- helpers

    function _frV(uint256 target, uint256 bps, uint256 vh) internal returns (uint256 id) {
        vm.prank(creator);
        lp.createFundraiseVested{value: FEE}("FR", "FR", "uri", TOTAL, target, bps, vh);
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

    function _status(uint256 id) internal view returns (uint8 st) {
        (,,,,,,,,, st,) = lp.fundraises(id);
    }

    function _alloc(uint256 id, address who) internal view returns (uint256 t) {
        (, t,,) = lp.fundraiseContribution(id, who);
    }

    function _flag(uint256 id, address who) internal view returns (bool c) {
        (,, c,) = lp.fundraiseContribution(id, who);
    }

    /// @dev 1 ETH target filled exactly by alice 0.5 / bob 0.3 / carol 0.2.
    function _fill(uint256 vh) internal returns (uint256 id, LaunchToken ft) {
        id = _frV(1 ether, 100, vh);
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

    function _claimReverts(address who, uint256 id, bytes4 sel) internal {
        vm.prank(who);
        vm.expectRevert(sel);
        lp.claim(id);
    }

    /// @dev Independent reference of the vesting schedule.
    function _vref(uint256 alloc, uint256 vh, uint256 t0) internal view returns (uint256) {
        if (vh == 0) return alloc;
        uint256 el = (block.timestamp - t0) / 3600;
        if (el >= vh) return alloc;
        return alloc * el / vh;
    }

    // ---------------------------------------------------------------- instant

    function test_DefaultCreateFundraiseIsInstant() public {
        vm.prank(creator);
        lp.createFundraise{value: FEE}("FR", "FR", "uri", TOTAL, 1 ether, 100);
        uint256 id = 0;
        (uint256 vh, uint256 lt) = lp.fundraiseVesting(id);
        assertEq(vh, 0);
        assertEq(lt, 0, "launchTime zero before fill");
        _contrib(alice, id, 0.6 ether);
        _contrib(bob, id, 0.4 ether);
        (, lt) = lp.fundraiseVesting(id);
        assertEq(lt, block.timestamp);
        LaunchToken ft = _tok(id);
        uint256 ta = _alloc(id, alice);
        assertEq(lp.claimableOf(id, alice), ta);
        vm.expectEmit(true, true, false, true, address(lp));
        emit KgiwaLaunchpad.Claimed(id, alice, ta);
        assertEq(_claim(alice, id), ta);
        assertTrue(_flag(id, alice));
        assertEq(lp.claimableOf(id, alice), 0);
        _claimReverts(alice, id, PROCESSED);
        uint256 tb = _alloc(id, bob);
        _assertLocked(ft, tb);
        assertEq(_claim(bob, id), tb);
        _assertLocked(ft, 0);
    }

    function test_CreateVestedZeroIsInstant() public {
        (uint256 id, LaunchToken ft) = _fill(0);
        (uint256 vh, uint256 lt) = lp.fundraiseVesting(id);
        assertEq(vh, 0);
        assertEq(lt, block.timestamp);
        uint256 sum;
        address[3] memory u = [alice, bob, carol];
        for (uint256 i; i < 3; ++i) {
            uint256 a = _alloc(id, u[i]);
            assertEq(lp.claimableOf(id, u[i]), a);
            assertEq(_claim(u[i], id), a);
            assertTrue(_flag(id, u[i]));
            sum += a;
        }
        assertEq(CURVE - _info(ft).inv, sum);
        _assertLocked(ft, 0);
    }

    // ---------------------------------------------------------------- schedules

    function _schedule(uint256 vh) internal {
        (uint256 id, LaunchToken ft) = _fill(vh);
        uint256 t0 = block.timestamp;
        (uint256 hrs, uint256 lt) = lp.fundraiseVesting(id);
        assertEq(hrs, vh);
        assertEq(lt, t0, "vesting starts at fill");
        uint256 a = _alloc(id, alice);
        uint256 b = _alloc(id, bob);

        // nothing at launch and at +59m59s
        assertEq(lp.claimableOf(id, alice), 0);
        _claimReverts(alice, id, NOTHING);
        vm.warp(t0 + 1 hours - 1);
        assertEq(lp.claimableOf(id, alice), 0);
        _claimReverts(alice, id, NOTHING);

        uint256 paid;
        for (uint256 k = 1; k <= vh; ++k) {
            vm.warp(t0 + k * 1 hours);
            assertEq(lp.claimableOf(id, bob), b * k / vh, "bob k/N (floor), never claimed yet");
            assertEq(lp.claimableOf(id, alice), a * k / vh - paid);
            vm.warp(t0 + k * 1 hours + 3599);
            assertEq(lp.claimableOf(id, alice), a * k / vh - paid, "steps are hourly, not continuous");
            vm.warp(t0 + k * 1 hours);
            uint256 got = _claim(alice, id);
            assertEq(got, a * k / vh - paid);
            paid += got;
            assertEq(ft.balanceOf(alice), a * k / vh);
            assertEq(_flag(id, alice), k == vh, "claimed flag only when fully claimed");
            if (k == 1) assertEq(got, a / vh, "exactly 1/N (floor) after one hour");
        }
        assertEq(paid, a);
        _claimReverts(alice, id, PROCESSED);

        // later: bob (never claimed) gets everything at once, nothing more ever vests
        vm.warp(t0 + vh * 1 hours + 1000 days);
        assertEq(lp.claimableOf(id, bob), b);
        assertEq(_claim(bob, id), b);
        _claimReverts(bob, id, PROCESSED);
        assertEq(lp.claimableOf(id, alice), 0);
    }

    function test_Vesting24_Schedule() public {
        _schedule(24);
    }

    function test_Vesting48_Schedule() public {
        _schedule(48);
    }

    function test_Vesting24_FullExactlyAt24h_NotBefore() public {
        (uint256 id,) = _fill(24);
        uint256 t0 = block.timestamp;
        uint256 a = _alloc(id, alice);
        vm.warp(t0 + 24 hours - 1);
        assertEq(lp.claimableOf(id, alice), a * 23 / 24);
        assertLt(a * 23 / 24, a);
        vm.warp(t0 + 24 hours);
        assertEq(lp.claimableOf(id, alice), a);
    }

    function test_Vesting48_HalfwayAndFull() public {
        (uint256 id,) = _fill(48);
        uint256 t0 = block.timestamp;
        uint256 a = _alloc(id, alice);
        vm.warp(t0 + 24 hours);
        assertEq(lp.claimableOf(id, alice), a / 2);
        vm.warp(t0 + 48 hours);
        assertEq(lp.claimableOf(id, alice), a);
    }

    // ---------------------------------------------------------------- repeated claims

    function _multiClaim(uint256 vh) internal {
        (uint256 id, LaunchToken ft) = _fill(vh);
        uint256 t0 = block.timestamp;
        address[3] memory u = [alice, bob, carol];
        uint256[6] memory hrs = [uint256(1), 5, 13, 13, 30, 60];
        for (uint256 i; i < hrs.length; ++i) {
            vm.warp(t0 + hrs[i] * 1 hours + (i * 997) % 3600);
            for (uint256 j; j < 3; ++j) {
                uint256 c = lp.claimableOf(id, u[j]);
                if (c != 0) assertEq(_claim(u[j], id), c, "claim pays claimableOf");
                assertEq(ft.balanceOf(u[j]), _vref(_alloc(id, u[j]), vh, t0), "balance == vested");
            }
        }
        uint256 sum;
        for (uint256 j; j < 3; ++j) {
            assertEq(ft.balanceOf(u[j]), _alloc(id, u[j]), "no stranded dust");
            assertTrue(_flag(id, u[j]));
            _claimReverts(u[j], id, PROCESSED);
            sum += _alloc(id, u[j]);
        }
        _assertLocked(ft, 0);
        assertEq(ft.balanceOf(address(lp)), LOCKED + CURVE - sum);
    }

    function test_MultiContributorRepeatedClaims_24h() public {
        _multiClaim(24);
    }

    function test_MultiContributorRepeatedClaims_48h() public {
        _multiClaim(48);
    }

    function testFuzz_FuzzedAllocationsClaimExactly(uint256 a, uint256 b, uint256 vhSel, uint256 s) public {
        uint256[3] memory opts = [uint256(0), 24, 48];
        uint256 vh = opts[vhSel % 3];
        a = bound(a, 0.01 ether, 9 ether);
        b = bound(b, 0.01 ether, 9 ether);
        uint256 id = _frV(20 ether, 100, vh);
        _contrib(alice, id, a);
        _contrib(bob, id, b);
        _contrib(carol, id, 25 ether); // capped at the remainder
        uint256 t0 = block.timestamp;
        uint256 t = t0;
        for (uint256 r; r < 3; ++r) {
            t += uint256(keccak256(abi.encode(s, r))) % (30 hours);
            vm.warp(t);
            _claimAllChecked(id, t0, vh);
        }
        vm.warp(t0 + vh * 1 hours + 1);
        _claimAllChecked(id, t0, vh);
        address[3] memory u = [alice, bob, carol];
        LaunchToken ft = _tok(id);
        for (uint256 j; j < 3; ++j) {
            assertEq(ft.balanceOf(u[j]), _alloc(id, u[j]), "released exactly the allocation");
            assertTrue(_flag(id, u[j]));
        }
        _assertLocked(ft, 0);
        _assertLedger();
    }

    function _claimAllChecked(uint256 id, uint256 t0, uint256 vh) internal {
        address[3] memory u = [alice, bob, carol];
        LaunchToken ft = _tok(id);
        for (uint256 j; j < 3; ++j) {
            uint256 c = lp.claimableOf(id, u[j]);
            if (c != 0) assertEq(_claim(u[j], id), c);
            uint256 v = _vref(_alloc(id, u[j]), vh, t0);
            assertEq(ft.balanceOf(u[j]), v, "never over- or under-released");
            assertLe(v, _alloc(id, u[j]));
        }
    }

    // ---------------------------------------------------------------- claim revert paths

    function test_SecondClaimSameHourReverts() public {
        (uint256 id,) = _fill(24);
        uint256 t0 = block.timestamp;
        uint256 a = _alloc(id, alice);
        vm.warp(t0 + 1 hours);
        _claim(alice, id);
        _claimReverts(alice, id, NOTHING);
        vm.warp(t0 + 2 hours - 1);
        _claimReverts(alice, id, NOTHING);
        vm.warp(t0 + 2 hours);
        assertEq(_claim(alice, id), a * 2 / 24 - a / 24);
    }

    function test_ClaimAfterFullyClaimedReverts() public {
        (uint256 id,) = _fill(24);
        vm.warp(block.timestamp + 24 hours);
        _claim(alice, id);
        assertTrue(_flag(id, alice));
        _claimReverts(alice, id, PROCESSED);
        vm.warp(block.timestamp + 100 days);
        _claimReverts(alice, id, PROCESSED);
    }

    function test_NonContributorClaimReverts() public {
        (uint256 id,) = _fill(24);
        _claimReverts(dave, id, NOTHING);
        vm.warp(block.timestamp + 24 hours);
        assertEq(lp.claimableOf(id, dave), 0);
        _claimReverts(dave, id, NOTHING);
        vm.warp(block.timestamp + 1000 days);
        _claimReverts(dave, id, NOTHING);
    }

    function test_ClaimBeforeLaunchReverts() public {
        uint256 id = _frV(1 ether, 100, 24);
        _contrib(alice, id, 0.5 ether);
        (uint256 vh, uint256 lt) = lp.fundraiseVesting(id);
        assertEq(vh, 24);
        assertEq(lt, 0);
        assertEq(lp.claimableOf(id, alice), 0);
        _claimReverts(alice, id, STATUS);
        vm.warp(block.timestamp + 10 days);
        _claimReverts(alice, id, STATUS);
    }

    function test_ClaimUnknownFundraiseReverts() public {
        vm.expectRevert(KgiwaLaunchpad.InvalidFundraise.selector);
        lp.claimableOf(7, alice);
        vm.expectRevert(KgiwaLaunchpad.InvalidFundraise.selector);
        lp.fundraiseVesting(7);
    }

    // ---------------------------------------------------------------- events / views / pause

    function test_ClaimedEventReportsAmountPaidEachClaim() public {
        (uint256 id,) = _fill(24);
        uint256 t0 = block.timestamp;
        uint256 a = _alloc(id, alice);
        vm.warp(t0 + 3 hours);
        vm.expectEmit(true, true, false, true, address(lp));
        emit KgiwaLaunchpad.Claimed(id, alice, a * 3 / 24);
        vm.prank(alice);
        lp.claim(id);
        vm.warp(t0 + 100 hours);
        vm.expectEmit(true, true, false, true, address(lp));
        emit KgiwaLaunchpad.Claimed(id, alice, a - a * 3 / 24);
        vm.prank(alice);
        lp.claim(id);
    }

    function test_ClaimableOfMatchesClaimAtEveryHour() public {
        (uint256 id,) = _fill(48);
        uint256 t0 = block.timestamp;
        for (uint256 k = 1; k <= 50; k += 7) {
            vm.warp(t0 + k * 1 hours + 123);
            uint256 c = lp.claimableOf(id, bob);
            vm.expectEmit(true, true, false, true, address(lp));
            emit KgiwaLaunchpad.Claimed(id, bob, c);
            assertEq(_claim(bob, id), c);
            assertEq(lp.claimableOf(id, bob), 0);
        }
    }

    function test_ClaimWorksWhilePaused() public {
        (uint256 id, LaunchToken ft) = _fill(24);
        vm.prank(owner);
        lp.setPaused(true);
        vm.warp(block.timestamp + 12 hours);
        uint256 a = _alloc(id, alice);
        assertEq(_claim(alice, id), a / 2);
        vm.warp(block.timestamp + 12 hours);
        assertEq(_claim(alice, id), a - a / 2);
        assertEq(ft.balanceOf(alice), a);
    }

    // ---------------------------------------------------------------- creation rules

    function test_InvalidVestingHoursRevert() public {
        uint256[9] memory bad = [uint256(1), 12, 23, 25, 47, 49, 72, 168, type(uint256).max];
        uint256 pb = platform.balance;
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(creator);
            vm.expectRevert(KgiwaLaunchpad.InvalidVesting.selector);
            lp.createFundraiseVested{value: FEE}("FR", "FR", "uri", TOTAL, 1 ether, 100, bad[i]);
        }
        assertEq(lp.fundraiseCount(), 0);
        assertEq(platform.balance, pb, "no fee taken");
        assertEq(address(lp).balance, 0);
    }

    function test_ValidVestingHoursCreateAndEmit() public {
        uint256[3] memory ok = [uint256(0), 24, 48];
        uint256 pb = platform.balance;
        for (uint256 i; i < ok.length; ++i) {
            vm.expectEmit(true, true, false, true, address(lp));
            emit KgiwaLaunchpad.FundraiseCreated(i, creator, 1 ether);
            uint256 id = _frV(1 ether, 100, ok[i]);
            (uint256 vh, uint256 lt) = lp.fundraiseVesting(id);
            assertEq(vh, ok[i]);
            assertEq(lt, 0);
            assertEq(_status(id), 0);
        }
        assertEq(platform.balance - pb, 3 * FEE);
        assertEq(address(lp).balance, 0, "fee forwarded, nothing stranded");
    }

    function test_VestedCreationFeeRules() public {
        uint256[4] memory wrong = [uint256(0), FEE - 1, FEE + 1, 1 ether];
        for (uint256 i; i < wrong.length; ++i) {
            vm.prank(creator);
            vm.expectRevert(KgiwaLaunchpad.InvalidPayment.selector);
            lp.createFundraiseVested{value: wrong[i]}("FR", "FR", "uri", TOTAL, 1 ether, 100, 24);
        }
        vm.prank(owner);
        lp.setFundraiseCreationFee(0.2 ether);
        vm.prank(creator);
        vm.expectRevert(KgiwaLaunchpad.InvalidPayment.selector);
        lp.createFundraiseVested{value: FEE}("FR", "FR", "uri", TOTAL, 1 ether, 100, 48);
        uint256 pb = platform.balance;
        vm.prank(creator);
        lp.createFundraiseVested{value: 0.2 ether}("FR", "FR", "uri", TOTAL, 1 ether, 100, 48);
        assertEq(platform.balance - pb, 0.2 ether);
        // invalid vesting rejected even when the fee is right; wrong fee + invalid vesting also reverts
        vm.prank(creator);
        vm.expectRevert(KgiwaLaunchpad.InvalidVesting.selector);
        lp.createFundraiseVested{value: 0.2 ether}("FR", "FR", "uri", TOTAL, 1 ether, 100, 12);
        vm.prank(creator);
        vm.expectRevert();
        lp.createFundraiseVested{value: 1}("FR", "FR", "uri", TOTAL, 1 ether, 100, 12);
    }

    function test_VestedCreationOtherValidationsAndPause() public {
        vm.startPrank(creator);
        vm.expectRevert(KgiwaLaunchpad.InvalidTarget.selector);
        lp.createFundraiseVested{value: FEE}("FR", "FR", "", TOTAL, 0.001 ether, 100, 24);
        vm.expectRevert(KgiwaLaunchpad.InvalidTarget.selector);
        lp.createFundraiseVested{value: FEE}("FR", "FR", "", TOTAL, 51 ether, 100, 24);
        vm.expectRevert(KgiwaLaunchpad.InvalidFee.selector);
        lp.createFundraiseVested{value: FEE}("FR", "FR", "", TOTAL, 1 ether, 99, 24);
        vm.expectRevert(KgiwaLaunchpad.InvalidSupply.selector);
        lp.createFundraiseVested{value: FEE}("FR", "FR", "", TOTAL - 1, 1 ether, 100, 24);
        vm.expectRevert(KgiwaLaunchpad.InvalidMetadata.selector);
        lp.createFundraiseVested{value: FEE}("", "FR", "", TOTAL, 1 ether, 100, 24);
        vm.stopPrank();
        vm.prank(owner);
        lp.setPaused(true);
        vm.prank(creator);
        vm.expectRevert(KgiwaLaunchpad.LaunchpadPaused.selector);
        lp.createFundraiseVested{value: FEE}("FR", "FR", "", TOTAL, 1 ether, 100, 24);
        vm.prank(creator);
        vm.expectRevert(KgiwaLaunchpad.LaunchpadPaused.selector);
        lp.createFundraise{value: FEE}("FR", "FR", "", TOTAL, 1 ether, 100);
    }
}

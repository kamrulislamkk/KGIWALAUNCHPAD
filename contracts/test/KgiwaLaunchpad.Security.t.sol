// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {KgiwaLaunchpadTestBase, Ref, TI} from "./KgiwaLaunchpad.Base.t.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";

contract ReenteringSeller {
    KgiwaLaunchpad internal lp;
    address internal tk;
    bool internal attack;

    constructor(KgiwaLaunchpad lp_) {
        lp = lp_;
    }

    function buy(address token) external payable {
        tk = token;
        lp.buy{value: msg.value}(token, 0);
    }

    function sell(uint256 amt) external {
        LaunchToken(tk).approve(address(lp), amt);
        attack = true;
        lp.sell(tk, amt, 0);
    }

    receive() external payable {
        if (attack) lp.buy{value: 0.001 ether}(tk, 0);
    }
}

contract KgiwaLaunchpadSecurityTest is KgiwaLaunchpadTestBase {
    LaunchToken internal t;

    function setUp() public override {
        super.setUp();
        t = _create(100);
    }

    // ---- (11) supply / access

    function test_OnlyLaunchpadCanBurnAddRewardsConsumeRewards() public {
        _buy(alice, t, 1 ether);
        address[3] memory callers = [alice, creator, owner];
        for (uint256 i; i < callers.length; ++i) {
            vm.startPrank(callers[i]);
            vm.expectRevert(abi.encodeWithSignature("OnlyLaunchpad()"));
            t.burn(1);
            vm.expectRevert(abi.encodeWithSignature("OnlyLaunchpad()"));
            t.addRewards(1);
            vm.expectRevert(abi.encodeWithSignature("OnlyLaunchpad()"));
            t.consumeRewards(alice);
            vm.stopPrank();
        }
        assertEq(t.launchpad(), address(lp));
    }

    function test_TokenHasNoMintPathAndConstructorChecks() public {
        (bool ok,) = address(t).call(abi.encodeWithSignature("mint(address,uint256)", alice, 1));
        assertFalse(ok);
        vm.expectRevert(abi.encodeWithSignature("InvalidSupply()"));
        new LaunchToken("A", "A", TOTAL - 1, address(this));
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new LaunchToken("A", "A", TOTAL, alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new LaunchToken("A", "A", TOTAL, address(0));
        LaunchToken d = new LaunchToken("A", "A", TOTAL, address(this));
        assertEq(d.totalSupply(), TOTAL);
        assertEq(d.balanceOf(address(this)), TOTAL);
    }

    function test_LaunchTokenRewardGuards() public {
        LaunchToken d = new LaunchToken("D", "D", TOTAL, address(this)); // this == launchpad
        vm.expectRevert(abi.encodeWithSignature("NoCirculatingSupply()"));
        d.addRewards(1 ether);
        d.transfer(alice, 999e18);
        vm.expectRevert(abi.encodeWithSignature("NoCirculatingSupply()"));
        d.addRewards(1 ether);
        d.transfer(alice, 1e18);
        d.addRewards(1 ether);
        assertApproxEqAbs(d.pendingRewards(alice), 1 ether, 1);
        assertEq(d.pendingRewards(address(this)), 0);
        assertEq(d.pendingRewards(address(0)), 0);
        uint256 owed = d.consumeRewards(alice);
        assertApproxEqAbs(owed, 1 ether, 1);
        assertEq(d.pendingRewards(alice), 0);
        d.burn(1e18);
        assertEq(d.totalSupply(), TOTAL - 1e18);
    }

    function test_SupplyNeverAboveTotalAndLockedAlwaysHeld() public {
        uint256 last = t.totalSupply();
        address[3] memory who = [alice, bob, carol];
        for (uint256 r; r < 4; ++r) {
            for (uint256 i; i < 3; ++i) {
                _buy(who[i], t, (r + 1) * (i + 1) * 2 ether);
                assertLe(t.totalSupply(), last);
                last = t.totalSupply();
                assertGe(t.balanceOf(address(lp)), LOCKED);
            }
            _sell(who[r % 3], t, t.balanceOf(who[r % 3]) / 2);
            assertLe(t.totalSupply(), last);
            last = t.totalSupply();
            _assertLocked(t, 0);
            _assertBacked(t);
        }
        assertLe(t.totalSupply(), TOTAL);
        _fillCurve(dave, t);
        assertGe(t.balanceOf(address(lp)), LOCKED);
        assertEq(t.balanceOf(address(lp)), LOCKED);
        assertLe(t.totalSupply(), last);
    }

    // ---- (13) pause

    function test_PauseOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        lp.setPaused(true);
        vm.prank(owner);
        lp.setPaused(true);
        assertTrue(lp.paused());
        vm.prank(owner);
        lp.setPaused(false);
        assertFalse(lp.paused());
    }

    function test_PauseBlocksCreateBuySellContribute() public {
        uint256 got = _buy(alice, t, 1 ether);
        vm.prank(creator);
        lp.createFundraise{value: 0.05 ether}("FR", "FR", "", TOTAL, 1 ether, 100);
        vm.prank(owner);
        lp.setPaused(true);
        bytes memory err = abi.encodeWithSignature("LaunchpadPaused()");

        vm.prank(creator);
        vm.expectRevert(err);
        lp.createInstant{value: 1 ether}("T", "T", "", TOTAL, 100);
        vm.prank(creator);
        vm.expectRevert(err);
        lp.createFundraise{value: 0.05 ether}("T", "T", "", TOTAL, 1 ether, 100);
        vm.prank(alice);
        vm.expectRevert(err);
        lp.buy{value: 1 ether}(address(t), 0);
        vm.prank(alice);
        t.approve(address(lp), got);
        vm.prank(alice);
        vm.expectRevert(err);
        lp.sell(address(t), got, 0);
        vm.prank(alice);
        vm.expectRevert(err);
        lp.contribute{value: 1 ether}(0);

        vm.prank(owner);
        lp.setPaused(false);
        _buy(bob, t, 1 ether); // trading resumes
    }

    function test_PauseDoesNotBlockExits() public {
        // token with holders + creator fees
        _buy(alice, t, 10 ether);
        // fundraise 0 filled (claim pending), fundraise 1 active w/ contribution (to cancel+refund), 2 active (to cancel)
        vm.startPrank(creator);
        lp.createFundraise{value: 0.05 ether}("F0", "F0", "", TOTAL, 1 ether, 100);
        lp.createFundraise{value: 0.05 ether}("F1", "F1", "", TOTAL, 1 ether, 100);
        vm.stopPrank();
        vm.prank(bob);
        lp.contribute{value: 1 ether}(0); // fills
        vm.prank(carol);
        lp.contribute{value: 0.5 ether}(1);

        vm.prank(owner);
        lp.setPaused(true);

        uint256 pend = lp.pendingHolderRewards(address(t), alice);
        assertGt(pend, 0);
        vm.prank(alice);
        lp.claimHolderRewards(address(t));
        vm.prank(creator);
        lp.claimCreatorFees(address(t));
        vm.prank(bob);
        lp.claim(0);
        (,, uint8 st0, address ftok) = _frS(0);
        assertEq(st0, 1);
        assertGt(LaunchToken(ftok).balanceOf(bob), 0);
        vm.prank(creator);
        lp.cancelFundraise(1);
        assertEq(_refund(carol, 1), 0.5 ether);
        _assertLedger();
    }

    function _frS(uint256 id) internal view returns (uint256 raised, uint256 price, uint8 status, address token) {
        (,,,,,, raised, price,, status, token) = lp.fundraises(id);
    }

    function test_ExpiredRefundWorksWhilePaused() public {
        vm.prank(creator);
        lp.createFundraise{value: 0.05 ether}("F", "F", "", TOTAL, 5 ether, 100);
        vm.prank(alice);
        lp.contribute{value: 1 ether}(0);
        vm.prank(owner);
        lp.setPaused(true);
        vm.warp(block.timestamp + 31 days);
        assertEq(_refund(alice, 0), 1 ether);
    }

    // ---- ownership & admin

    function test_RenounceOwnershipReverts() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("RenounceDisabled()"));
        lp.renounceOwnership();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        lp.renounceOwnership();
        assertEq(lp.owner(), owner);
    }

    function test_TransferOwnershipStillWorks() public {
        vm.prank(owner);
        lp.transferOwnership(bob);
        assertEq(lp.owner(), bob);
        vm.prank(bob);
        lp.setPaused(true);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner));
        lp.setPaused(false);
    }

    function test_PlatformWalletAdmin() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new KgiwaLaunchpad(owner, address(0));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        lp.setPlatformWallet(address(0));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        lp.setPlatformWallet(alice);
        address w2 = makeAddr("platform2");
        vm.prank(owner);
        lp.setPlatformWallet(w2);
        uint256 b = w2.balance;
        _buy(alice, t, 10 ether);
        assertEq(w2.balance - b, 0.04 ether, "new wallet gets platform share");
    }

    // ---- reentrancy through the ETH payout

    function test_SellPayoutReentrancyBlocked() public {
        ReenteringSeller atk = new ReenteringSeller(lp);
        vm.deal(address(atk), 10 ether);
        atk.buy{value: 5 ether}(address(t));
        uint256 bal = t.balanceOf(address(atk));
        assertGt(bal, 0);
        vm.expectRevert(abi.encodeWithSignature("ETHTransferFailed()"));
        atk.sell(bal);
        assertEq(t.balanceOf(address(atk)), bal, "failed sell fully reverted");
        _assertLedger();
    }
}

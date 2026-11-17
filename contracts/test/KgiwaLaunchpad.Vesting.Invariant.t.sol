// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";
import {TI, tinfo} from "./KgiwaLaunchpad.Base.t.sol";

/// @dev Bounded action surface over VESTED fundraises (0/24/48h). Tracks ghost claimed amounts.
contract VestingHandler is Test {
    uint256 internal constant MIN_TRADE = 0.00001 ether;

    KgiwaLaunchpad public lp;
    address public owner;
    address[] internal _actors;

    mapping(uint256 => mapping(address => uint256)) public ghostClaimed; // id => user => tokens
    mapping(address => uint256) public lastSupply;
    bool public supplyIncreased;
    bool public claimMismatch; // claim paid != claimableOf, or a claimable>0 claim reverted
    uint256 public nCreate;
    uint256 public nFill;
    uint256 public nClaim;
    uint256 public nPartialClaim;
    uint256 public nTrade;

    constructor(KgiwaLaunchpad lp_, address owner_, address[] memory actors_) {
        lp = lp_;
        owner = owner_;
        for (uint256 i; i < actors_.length; ++i) {
            _actors.push(actors_[i]);
            vm.deal(actors_[i], 10_000_000 ether);
        }
    }

    function actorCount() external view returns (uint256) {
        return _actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return _actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    function _sync() internal {
        uint256 n = lp.tokenCount();
        for (uint256 i; i < n; ++i) {
            address tk = lp.tokenAt(i);
            uint256 s = LaunchToken(tk).totalSupply();
            uint256 l = lastSupply[tk];
            if (l != 0 && s > l) supplyIncreased = true;
            lastSupply[tk] = s;
        }
    }

    function _launchedToken(uint256 seed) internal view returns (address tk) {
        uint256 n = lp.fundraiseCount();
        if (n == 0) return address(0);
        (,,,,,,,,,, tk) = lp.fundraises(seed % n);
    }

    function createVested(uint256 targetSeed, uint256 vhSeed, uint256 creatorSeed) external {
        if (lp.fundraiseCount() >= 4) return;
        uint256 target = bound(targetSeed, 0.5 ether, 6 ether);
        uint256 vh = (vhSeed % 3) * 24;
        uint256 fee = lp.fundraiseCreationFee();
        vm.prank(_actor(creatorSeed));
        try lp.createFundraiseVested{value: fee}("FR", "FR", "", 1_000_000_000e18, target, 100 + vhSeed % 201, vh) {
            ++nCreate;
        } catch {}
    }

    function contribute(uint256 aSeed, uint256 fSeed, uint256 amt) external {
        uint256 n = lp.fundraiseCount();
        if (n == 0) return;
        uint256 id = fSeed % n;
        amt = bound(amt, 0.01 ether, 4 ether);
        (,,,,,,,,, uint8 before,) = lp.fundraises(id);
        vm.prank(_actor(aSeed));
        try lp.contribute{value: amt}(id) {
            (,,,,,,,,, uint8 st,) = lp.fundraises(id);
            if (before == 0 && st == 1) ++nFill;
        } catch {}
        _sync();
    }

    function claim(uint256 aSeed, uint256 fSeed) external {
        uint256 n = lp.fundraiseCount();
        if (n == 0) return;
        uint256 id = fSeed % n;
        (,,,,,,,,, uint8 st, address tk) = lp.fundraises(id);
        if (st != 1) return;
        address who;
        for (uint256 i; i < _actors.length; ++i) {
            who = _actors[(aSeed % _actors.length + i) % _actors.length];
            (uint256 eth,,,) = lp.fundraiseContribution(id, who);
            if (eth > 0) break;
        }
        uint256 expected = lp.claimableOf(id, who);
        uint256 b = LaunchToken(tk).balanceOf(who);
        vm.prank(who);
        try lp.claim(id) {
            uint256 got = LaunchToken(tk).balanceOf(who) - b;
            if (got != expected) claimMismatch = true;
            ghostClaimed[id][who] += got;
            ++nClaim;
            (, uint256 alloc,,) = lp.fundraiseContribution(id, who);
            if (ghostClaimed[id][who] < alloc) ++nPartialClaim;
        } catch {
            // claims are allowed while paused; a vested amount must always be claimable
            if (expected != 0) claimMismatch = true;
        }
        _sync();
    }

    function buy(uint256 aSeed, uint256 fSeed, uint256 amt) external {
        address tk = _launchedToken(fSeed);
        if (tk == address(0)) return;
        vm.prank(_actor(aSeed));
        try lp.buy{value: bound(amt, MIN_TRADE, 3 ether)}(tk, 0) {
            ++nTrade;
        } catch {}
        _sync();
    }

    function sell(uint256 aSeed, uint256 fSeed, uint256 pct) external {
        address tk = _launchedToken(fSeed);
        if (tk == address(0)) return;
        address a;
        for (uint256 i; i < _actors.length; ++i) {
            a = _actors[(aSeed % _actors.length + i) % _actors.length];
            if (LaunchToken(tk).balanceOf(a) > 0) break;
        }
        uint256 amt = LaunchToken(tk).balanceOf(a) * bound(pct, 1, 100) / 100;
        if (amt == 0) return;
        vm.prank(a);
        LaunchToken(tk).approve(address(lp), amt);
        vm.prank(a);
        try lp.sell(tk, amt, 0) {
            ++nTrade;
        } catch {}
        _sync();
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 0, 5 hours));
    }

    function togglePause(uint256 seed) external {
        vm.prank(owner);
        lp.setPaused(seed % 6 == 0);
    }
}

contract KgiwaLaunchpadVestingInvariantTest is Test {
    uint256 internal constant TOTAL = 1_000_000_000e18;
    uint256 internal constant CURVE = 800_000_000e18;
    uint256 internal constant LOCKED = 200_000_000e18;

    KgiwaLaunchpad internal lp;
    VestingHandler internal h;
    address internal owner = makeAddr("owner");
    address internal platform = makeAddr("platform");
    address[] internal actors;

    function setUp() public {
        lp = new KgiwaLaunchpad(owner, platform);
        for (uint256 i; i < 5; ++i) actors.push(makeAddr(string(abi.encodePacked("vactor", vm.toString(i)))));
        h = new VestingHandler(lp, owner, actors);
        targetContract(address(h));
        bytes4[] memory sels = new bytes4[](14);
        sels[0] = h.createVested.selector;
        sels[1] = h.createVested.selector;
        sels[2] = h.contribute.selector;
        sels[3] = h.contribute.selector;
        sels[4] = h.contribute.selector;
        sels[5] = h.claim.selector;
        sels[6] = h.claim.selector;
        sels[7] = h.claim.selector;
        sels[8] = h.warp.selector;
        sels[9] = h.warp.selector;
        sels[10] = h.buy.selector;
        sels[11] = h.sell.selector;
        sels[12] = h.sell.selector;
        sels[13] = h.togglePause.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: sels}));
    }

    function afterInvariant() public view {
        console2.log("vested create/fill/claim", h.nCreate(), h.nFill(), h.nClaim());
        console2.log(" partial claims/trades", h.nPartialClaim(), h.nTrade());
    }

    function _vref(uint256 id, uint256 alloc) internal view returns (uint256) {
        (uint256 vh, uint256 lt) = lp.fundraiseVesting(id);
        if (vh == 0) return alloc;
        uint256 el = (block.timestamp - lt) / 1 hours;
        if (el >= vh) return alloc;
        return alloc * el / vh;
    }

    /// forge-config: default.invariant.runs = 48
    /// forge-config: default.invariant.depth = 100
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_VestedLockedBalanceReserveAndSupply() public view {
        uint256 m = lp.fundraiseCount();
        for (uint256 id; id < m; ++id) {
            (,,,,,,,,, uint8 st, address tk) = lp.fundraises(id);
            if (st != 1) continue;
            LaunchToken lt = LaunchToken(tk);
            uint256 unclaimed;
            for (uint256 a; a < actors.length; ++a) {
                (, uint256 alloc,,) = lp.fundraiseContribution(id, actors[a]);
                unclaimed += alloc - h.ghostClaimed(id, actors[a]);
            }
            TI memory t = tinfo(lp, tk);
            // launchpad token balance == 200M locked + curve inventory + unclaimed allocation
            assertEq(lt.balanceOf(address(lp)), LOCKED + t.inv + unclaimed, "launchpad balance accounting");
            assertGe(t.reserve, lp.reserveRequired(tk), "reserve < required");
            assertLe(lt.totalSupply(), TOTAL);
            // holder rewards exclude launchpad-held (unclaimed + inventory + locked) tokens
            uint256 held;
            uint256 pend;
            for (uint256 a; a < actors.length; ++a) {
                held += lt.balanceOf(actors[a]);
                pend += lp.pendingHolderRewards(tk, actors[a]);
            }
            assertEq(lt.circulating(), held, "circulating == tokens in user hands");
            assertLe(pend, lp.holderPool(tk), "pending rewards exceed pool");
            assertEq(lp.pendingHolderRewards(tk, address(lp)), 0);
        }
        assertFalse(h.supplyIncreased(), "a totalSupply rose");
    }

    /// forge-config: default.invariant.runs = 48
    /// forge-config: default.invariant.depth = 100
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_NeverOverReleasedAndClaimableMatches() public view {
        assertFalse(h.claimMismatch(), "claim paid != claimableOf, or vested claim reverted");
        uint256 m = lp.fundraiseCount();
        for (uint256 id; id < m; ++id) {
            (,,,,,,,,, uint8 st,) = lp.fundraises(id);
            for (uint256 a; a < actors.length; ++a) {
                (, uint256 alloc, bool claimed,) = lp.fundraiseContribution(id, actors[a]);
                uint256 got = h.ghostClaimed(id, actors[a]);
                assertLe(got, alloc, "released more than allocated");
                assertEq(claimed, alloc != 0 && got == alloc, "claimed flag == fully claimed");
                if (st != 1) {
                    assertEq(got, 0);
                    assertEq(lp.claimableOf(id, actors[a]), 0);
                    continue;
                }
                uint256 v = _vref(id, alloc);
                assertLe(got, v, "released more than vested");
                assertEq(lp.claimableOf(id, actors[a]), v - got, "claimable == vested - claimed");
            }
        }
    }
}

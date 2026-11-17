// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";
import {Ref, TI, tinfo} from "./KgiwaLaunchpad.Base.t.sol";

/// @dev Bounded action surface for the invariant fuzzer. Not a test contract (no test* functions).
contract KgiwaHandler is Test {
    uint256 internal constant MIN_TRADE = 0.00001 ether;
    uint256 internal constant CURVE = 800_000_000e18;

    KgiwaLaunchpad public lp;
    address public owner;
    address[] internal _actors;

    mapping(uint256 => uint256) public refunded; // fundraise id => ETH refunded
    mapping(address => uint256) public lastSupply;
    mapping(address => uint256) public claimedRewards;
    bool public supplyIncreased;
    uint256 public badReverts;
    bytes4 public lastBadSelector;

    // coverage counters
    uint256 public nCreate;
    uint256 public nBuy;
    uint256 public nSell;
    uint256 public nTransfer;
    uint256 public nRewardClaim;
    uint256 public nFees;
    uint256 public nFr;
    uint256 public nContribute;
    uint256 public nFill;
    uint256 public nFrClaim;
    uint256 public nRefund;
    uint256 public nCancel;

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

    // ------------------------------------------------------------ helpers

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    /// @dev Prefer an actor that holds tokens (rotates from the seed) so sells/transfers are meaningful.
    function _holder(uint256 seed, address tk) internal view returns (address) {
        for (uint256 i; i < _actors.length; ++i) {
            address a = _actors[(seed % _actors.length + i) % _actors.length];
            if (LaunchToken(tk).balanceOf(a) > 0) return a;
        }
        return _actors[seed % _actors.length];
    }

    function _contributor(uint256 seed, uint256 id) internal view returns (address) {
        for (uint256 i; i < _actors.length; ++i) {
            address a = _actors[(seed % _actors.length + i) % _actors.length];
            (uint256 eth,,,) = lp.fundraiseContribution(id, a);
            if (eth > 0) return a;
        }
        return _actors[seed % _actors.length];
    }

    function _token(uint256 seed) internal view returns (address) {
        uint256 n = lp.tokenCount();
        return n == 0 ? address(0) : lp.tokenAt(seed % n);
    }

    function _flag(bytes memory err, bool alsoInventory) internal {
        bytes4 sel = err.length >= 4 ? bytes4(err) : bytes4(0);
        if (
            sel == KgiwaLaunchpad.InsufficientReserve.selector || sel == KgiwaLaunchpad.CurveMathError.selector
                || sel == KgiwaLaunchpad.ETHTransferFailed.selector || sel == KgiwaLaunchpad.TokenTransferFailed.selector
                || sel == bytes4(0x4e487b71) || (alsoInventory && sel == KgiwaLaunchpad.InsufficientInventory.selector)
        ) {
            ++badReverts;
            lastBadSelector = sel;
        }
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

    // ------------------------------------------------------------ instant tokens

    function createToken(uint256 bpsSeed, uint256 creatorSeed, uint256 ethSeed) external {
        if (lp.tokenCount() >= 5) return;
        uint256 bps = bound(bpsSeed, 100, 300);
        uint256 extra = bound(ethSeed, 0, 20 ether);
        if (extra < MIN_TRADE) extra = 0;
        address c = _actor(creatorSeed);
        uint256 fee = lp.instantCreationFee();
        vm.prank(c);
        try lp.createInstant{value: fee + extra}("Tok", "TOK", "", 1_000_000_000e18, bps) {
            ++nCreate;
        } catch (bytes memory e) {
            _flag(e, true);
        }
        _sync();
    }

    function buy(uint256 aSeed, uint256 tSeed, uint256 amt) external {
        address tk = _token(tSeed);
        if (tk == address(0)) return;
        amt = bound(amt, MIN_TRADE, 60 ether);
        vm.prank(_actor(aSeed));
        try lp.buy{value: amt}(tk, 0) {
            ++nBuy;
        } catch (bytes memory e) {
            _flag(e, false);
        }
        _sync();
    }

    /// @dev Spend a fraction of whatever is left on the curve (drives the burn clamp / near-capacity regime).
    function buyNearCapacity(uint256 aSeed, uint256 tSeed, uint256 pct) external {
        address tk = _token(tSeed);
        if (tk == address(0)) return;
        TI memory i = tinfo(lp, tk);
        uint256 req = lp.reserveRequired(tk);
        uint256 cap = Ref.reserve(CURVE);
        if (cap <= req + 2e6) return;
        pct = bound(pct, 1, 100);
        uint256 v = (cap - req - 1e6) * 10_000 / (10_000 - i.bps) * pct / 100;
        if (v < MIN_TRADE || v > 5_000_000 ether) return;
        vm.prank(_actor(aSeed));
        try lp.buy{value: v}(tk, 0) {
            ++nBuy;
        } catch (bytes memory e) {
            _flag(e, false);
        }
        _sync();
    }

    function sell(uint256 aSeed, uint256 tSeed, uint256 pct) external {
        address tk = _token(tSeed);
        if (tk == address(0)) return;
        address a = _holder(aSeed, tk);
        uint256 bal = LaunchToken(tk).balanceOf(a);
        uint256 amt = bal * bound(pct, 1, 100) / 100;
        if (amt == 0) return;
        vm.prank(a);
        LaunchToken(tk).approve(address(lp), amt);
        vm.prank(a);
        try lp.sell(tk, amt, 0) {
            ++nSell;
        } catch (bytes memory e) {
            _flag(e, true);
        }
        _sync();
    }

    function transferTokens(uint256 aSeed, uint256 bSeed, uint256 tSeed, uint256 pct) external {
        address tk = _token(tSeed);
        if (tk == address(0)) return;
        address a = _holder(aSeed, tk);
        address b = _actor(bSeed);
        if (a == b) return;
        uint256 amt = LaunchToken(tk).balanceOf(a) * bound(pct, 1, 100) / 100;
        if (amt == 0) return;
        vm.prank(a);
        LaunchToken(tk).transfer(b, amt);
        ++nTransfer;
        _sync();
    }

    function claimRewards(uint256 aSeed, uint256 tSeed) external {
        address tk = _token(tSeed);
        if (tk == address(0)) return;
        address a = _holder(aSeed, tk);
        uint256 before = a.balance;
        vm.prank(a);
        try lp.claimHolderRewards(tk) {
            claimedRewards[tk] += a.balance - before;
            ++nRewardClaim;
        } catch (bytes memory e) {
            _flag(e, true);
        }
    }

    function claimCreatorFees(uint256 tSeed) external {
        address tk = _token(tSeed);
        if (tk == address(0)) return;
        address c = tinfo(lp, tk).creator;
        vm.prank(c);
        try lp.claimCreatorFees(tk) {
            ++nFees;
        } catch (bytes memory e) {
            _flag(e, true);
        }
    }

    // ------------------------------------------------------------ fundraises

    function createFundraise(uint256 targetSeed, uint256 bpsSeed, uint256 creatorSeed) external {
        if (lp.fundraiseCount() >= 5) return;
        uint256 target = bound(targetSeed, 0.01 ether, 50 ether);
        uint256 bps = bound(bpsSeed, 100, 300);
        uint256 fee = lp.fundraiseCreationFee();
        vm.prank(_actor(creatorSeed));
        try lp.createFundraise{value: fee}("FR", "FR", "", 1_000_000_000e18, target, bps) {
            ++nFr;
        } catch (bytes memory e) {
            _flag(e, true);
        }
    }

    function _fr(uint256 seed) internal view returns (bool ok, uint256 id) {
        uint256 n = lp.fundraiseCount();
        if (n == 0) return (false, 0);
        return (true, seed % n);
    }

    function contribute(uint256 aSeed, uint256 fSeed, uint256 amt) external {
        (bool ok, uint256 id) = _fr(fSeed);
        if (!ok) return;
        amt = bound(amt, MIN_TRADE, 30 ether);
        (,,,,,,,,, uint8 before,) = lp.fundraises(id);
        vm.prank(_actor(aSeed));
        try lp.contribute{value: amt}(id) {
            ++nContribute;
            (,,,,,,,,, uint8 st,) = lp.fundraises(id);
            if (before == 0 && st == 1) ++nFill;
        } catch (bytes memory e) {
            _flag(e, true);
        }
        _sync();
    }

    function claimFundraise(uint256 aSeed, uint256 fSeed) external {
        (bool ok, uint256 id) = _fr(fSeed);
        if (!ok) return;
        vm.prank(_contributor(aSeed, id));
        try lp.claim(id) {
            ++nFrClaim;
        } catch (bytes memory e) {
            _flag(e, true);
        }
        _sync();
    }

    function cancelFundraise(uint256 fSeed) external {
        (bool ok, uint256 id) = _fr(fSeed);
        if (!ok) return;
        (address c,,,,,,,,,,) = lp.fundraises(id);
        vm.prank(c);
        try lp.cancelFundraise(id) {
            ++nCancel;
        } catch (bytes memory e) {
            _flag(e, true);
        }
    }

    function refund(uint256 aSeed, uint256 fSeed) external {
        (bool ok, uint256 id) = _fr(fSeed);
        if (!ok) return;
        address a = _contributor(aSeed, id);
        uint256 before = a.balance;
        vm.prank(a);
        try lp.refund(id) {
            refunded[id] += a.balance - before;
            ++nRefund;
        } catch (bytes memory e) {
            _flag(e, true);
        }
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 0, 12 days));
    }

    function togglePause(uint256 seed) external {
        vm.prank(owner);
        lp.setPaused(seed % 8 == 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";

/// @dev Independent high-precision (1e27) reference math. Deliberately NOT a copy of the
/// contract's implementation: different range reduction / series / precision.
library Ref {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HP = 1e27;
    uint256 internal constant K = 2302585092994045684;
    uint256 internal constant C = 800_000_000e18;
    uint256 internal constant P0 = 250_000_000_000;
    uint256 internal constant A = P0 * (C / WAD) * WAD / K;
    uint256 internal constant LN2_HP = 693147180559945309417232121;

    /// @dev exp(x / 1e18) * 1e18 for x in [0, ln 10].
    function expWad(uint256 x) internal pure returns (uint256) {
        uint256 y = x * (HP / WAD) / 8;
        uint256 term = HP;
        uint256 sum = HP;
        for (uint256 i = 1; i <= 40; ++i) {
            term = term * y / HP / i;
            sum += term;
            if (term == 0) break;
        }
        for (uint256 j; j < 3; ++j) sum = sum * sum / HP;
        return sum / (HP / WAD);
    }

    /// @dev ln(x / 1e18) * 1e18 for x in [1, 10] WAD (halving + atanh series).
    function lnWad(uint256 x) internal pure returns (uint256) {
        uint256 z = x * (HP / WAD);
        uint256 k;
        while (z >= 2 * HP) {
            z /= 2;
            ++k;
        }
        uint256 u = (z - HP) * HP / (z + HP);
        uint256 u2 = u * u / HP;
        uint256 term = u;
        uint256 sum;
        for (uint256 i; i < 45; ++i) {
            sum += term / (2 * i + 1);
            term = term * u2 / HP;
            if (term == 0) break;
        }
        return (2 * sum + k * LN2_HP) / (HP / WAD);
    }

    function reserve(uint256 sold) internal pure returns (uint256) {
        return A * (expWad(K * sold / C) - WAD) / WAD;
    }

    function price(uint256 sold) internal pure returns (uint256) {
        return P0 * expWad(K * sold / C) / WAD;
    }

    /// @dev Ideal (un-floored) curve position after spending `net` wei from `sold`.
    function position(uint256 sold, uint256 net) internal pure returns (uint256) {
        uint256 target = reserve(sold) + net;
        return C * lnWad(WAD + target * WAD / A) / K;
    }
}

struct TI {
    address creator;
    uint256 supply;
    uint256 price;
    uint256 inv;
    uint256 reserve;
    uint256 volume;
    uint256 bps;
    bool launched;
}

function tinfo(KgiwaLaunchpad lp, address t) view returns (TI memory r) {
    (r.creator, r.supply, r.price, r.inv, r.reserve, r.volume, r.bps, r.launched) = lp.tokens(t);
}

abstract contract KgiwaLaunchpadTestBase is Test {
    uint256 internal constant TOTAL = 1_000_000_000e18;
    uint256 internal constant CURVE = 800_000_000e18;
    uint256 internal constant LOCKED = 200_000_000e18;
    uint256 internal constant MIN_TRADE = 0.00001 ether;
    uint256 internal constant P0 = 2.5e11;
    uint256 internal constant TOKEN_TOL = 1e12; // 1e-6 token absolute tolerance vs reference

    KgiwaLaunchpad internal lp;
    address internal owner = makeAddr("owner");
    address internal platform = makeAddr("platform");
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");

    function setUp() public virtual {
        lp = new KgiwaLaunchpad(owner, platform);
        address[5] memory a = [creator, alice, bob, carol, dave];
        for (uint256 i; i < a.length; ++i) vm.deal(a[i], 1_000_000 ether);
    }

    // ---------------------------------------------------------------- helpers

    /// @dev Create an instant token with only the creation fee (no first buy).
    function _create(uint256 bps) internal returns (LaunchToken t) {
        return _createWith(bps, lp.instantCreationFee());
    }

    function _createWith(uint256 bps, uint256 value) internal returns (LaunchToken t) {
        vm.prank(creator);
        lp.createInstant{value: value}("Token", "TKN", "ipfs://logo", TOTAL, bps);
        t = LaunchToken(lp.tokenAt(lp.tokenCount() - 1));
    }

    function _buy(address who, LaunchToken t, uint256 v) internal returns (uint256 got) {
        uint256 b = t.balanceOf(who);
        vm.prank(who);
        lp.buy{value: v}(address(t), 0);
        got = t.balanceOf(who) - b;
    }

    function _sell(address who, LaunchToken t, uint256 amt) internal returns (uint256 got) {
        vm.prank(who);
        t.approve(address(lp), amt);
        uint256 b = who.balance;
        vm.prank(who);
        lp.sell(address(t), amt, 0);
        got = who.balance - b;
    }

    function _info(LaunchToken t) internal view returns (TI memory) {
        return tinfo(lp, address(t));
    }

    function _sold(LaunchToken t) internal view returns (uint256) {
        return CURVE - _info(t).inv;
    }

    function _burned(LaunchToken t) internal view returns (uint256) {
        return TOTAL - t.totalSupply();
    }

    function _assertBacked(LaunchToken t) internal view {
        assertGe(_info(t).reserve, lp.reserveRequired(address(t)), "reserve < required");
    }

    /// @dev Launchpad's token balance == locked 200M + curve inventory + unclaimed fundraise allocations.
    function _assertLocked(LaunchToken t, uint256 unclaimed) internal view {
        uint256 bal = t.balanceOf(address(lp));
        assertGe(bal, LOCKED + unclaimed, "locked 200M breached");
        assertEq(bal, LOCKED + _info(t).inv + unclaimed, "lp balance != locked + inventory + unclaimed");
    }

    function _net(uint256 v, uint256 bps) internal pure returns (uint256) {
        return v - v * bps / 10_000;
    }

    /// @dev Drive a token's curve exactly to full inventory using one huge buy + fee-funded burn.
    function _fillCurve(address who, LaunchToken t) internal {
        TI memory i = _info(t);
        uint256 rem = Ref.reserve(CURVE) - lp.reserveRequired(address(t)) - 1e6;
        uint256 v = rem * 10_000 / (10_000 - i.bps);
        _buy(who, t, v);
        assertEq(_info(t).inv, 0, "curve not filled");
    }

    mapping(uint256 => uint256) internal ghostRefunded;

    function _refund(address who, uint256 id) internal returns (uint256 got) {
        uint256 b = who.balance;
        vm.prank(who);
        lp.refund(id);
        got = who.balance - b;
        ghostRefunded[id] += got;
    }

    /// @dev Exact ETH the launchpad must hold: reserves + holder pools + creator fees + unsettled fundraise ETH.
    function _expectedBalance() internal view returns (uint256 sum) {
        uint256 n = lp.tokenCount();
        for (uint256 i; i < n; ++i) {
            address tk = lp.tokenAt(i);
            sum += tinfo(lp, tk).reserve + lp.holderPool(tk) + lp.creatorFees(tk);
        }
        uint256 m = lp.fundraiseCount();
        for (uint256 id; id < m; ++id) {
            (,,,,, , uint256 raised,,, uint8 status,) = lp.fundraises(id);
            if (status != 1) sum += raised - ghostRefunded[id];
        }
    }

    function _assertLedger() internal view {
        assertEq(address(lp).balance, _expectedBalance(), "ETH ledger");
    }

    function _lastLog(bytes32 sig) internal returns (Vm.Log memory out, bool found) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) {
                out = logs[i];
                found = true;
            }
        }
    }
}

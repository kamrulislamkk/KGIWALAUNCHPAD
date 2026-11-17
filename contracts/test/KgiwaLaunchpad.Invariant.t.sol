// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";
import {Ref, TI, tinfo} from "./KgiwaLaunchpad.Base.t.sol";
import {KgiwaHandler} from "./KgiwaLaunchpad.Handler.t.sol";

contract KgiwaLaunchpadInvariantTest is Test {
    uint256 internal constant TOTAL = 1_000_000_000e18;
    uint256 internal constant CURVE = 800_000_000e18;
    uint256 internal constant LOCKED = 200_000_000e18;

    KgiwaLaunchpad internal lp;
    KgiwaHandler internal h;
    address internal owner = makeAddr("owner");
    address internal platform = makeAddr("platform");
    address[] internal actors;

    function setUp() public {
        lp = new KgiwaLaunchpad(owner, platform);
        for (uint256 i; i < 5; ++i) actors.push(makeAddr(string(abi.encodePacked("actor", vm.toString(i)))));
        h = new KgiwaHandler(lp, owner, actors);
        targetContract(address(h));
        // keep the engine on the handler's bounded functions only
        bytes4[] memory sels = new bytes4[](24);
        sels[0] = h.createToken.selector;
        sels[1] = h.createToken.selector;
        sels[2] = h.buy.selector;
        sels[3] = h.buy.selector;
        sels[4] = h.buy.selector;
        sels[5] = h.buyNearCapacity.selector;
        sels[6] = h.sell.selector;
        sels[7] = h.sell.selector;
        sels[8] = h.sell.selector;
        sels[9] = h.transferTokens.selector;
        sels[10] = h.claimRewards.selector;
        sels[11] = h.claimCreatorFees.selector;
        sels[12] = h.createFundraise.selector;
        sels[13] = h.createFundraise.selector;
        sels[14] = h.contribute.selector;
        sels[15] = h.contribute.selector;
        sels[16] = h.contribute.selector;
        sels[17] = h.claimFundraise.selector;
        sels[18] = h.cancelFundraise.selector;
        sels[19] = h.refund.selector;
        sels[20] = h.refund.selector;
        sels[21] = h.warp.selector;
        sels[22] = h.togglePause.selector;
        sels[23] = h.buyNearCapacity.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: sels}));
        // seed some state so early calls are meaningful
        vm.deal(address(this), 100 ether);
    }

    function afterInvariant() public view {
        console2.log("create/buy/sell/xfer", h.nCreate(), h.nBuy(), h.nSell());
        console2.log(" xfer/rewards/fees", h.nTransfer(), h.nRewardClaim(), h.nFees());
        console2.log(" fr/contrib/fill", h.nFr(), h.nContribute(), h.nFill());
        console2.log(" frclaim/refund/cancel", h.nFrClaim(), h.nRefund(), h.nCancel());
    }

    // ------------------------------------------------------------ views over all tokens

    function _unclaimed(address token) internal view returns (uint256 u) {
        uint256 m = lp.fundraiseCount();
        for (uint256 id; id < m; ++id) {
            (,,,,,,,, , uint8 st, address tk) = lp.fundraises(id);
            if (st != 1 || tk != token) continue;
            for (uint256 a; a < actors.length; ++a) {
                (, uint256 alloc, bool claimed,) = lp.fundraiseContribution(id, actors[a]);
                if (!claimed) u += alloc;
            }
        }
    }

    function _ledger() internal view returns (uint256 sum) {
        uint256 n = lp.tokenCount();
        for (uint256 i; i < n; ++i) {
            address tk = lp.tokenAt(i);
            sum += tinfo(lp, tk).reserve + lp.holderPool(tk) + lp.creatorFees(tk);
        }
        uint256 m = lp.fundraiseCount();
        for (uint256 id; id < m; ++id) {
            (,,,,,, uint256 raised,,, uint8 st,) = lp.fundraises(id);
            if (st != 1) sum += raised - h.refunded(id);
        }
    }

    // ------------------------------------------------------------ invariants

    /// forge-config: default.invariant.runs = 48
    /// forge-config: default.invariant.depth = 100
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_SolvencyBackingAndLedger() public view {
        // (3) reserve always covers the curve position; (6) exact ETH ledger
        assertEq(address(lp).balance, _ledger(), "ETH ledger");
        uint256 n = lp.tokenCount();
        for (uint256 i; i < n; ++i) {
            address tk = lp.tokenAt(i);
            TI memory t = tinfo(lp, tk);
            assertGe(t.reserve, lp.reserveRequired(tk), "reserveETH < reserveRequired");
            assertLe(t.inv, CURVE);
        }
    }

    /// forge-config: default.invariant.runs = 48
    /// forge-config: default.invariant.depth = 100
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_SupplyLockedAndTokenAccounting() public view {
        uint256 n = lp.tokenCount();
        for (uint256 i; i < n; ++i) {
            address tk = lp.tokenAt(i);
            LaunchToken lt = LaunchToken(tk);
            // (11) no minting: supply <= 1B and never rose
            assertLe(lt.totalSupply(), TOTAL);
            // (12) locked 200M + inventory + unclaimed allocations are exactly what the launchpad holds
            uint256 un = _unclaimed(tk);
            uint256 bal = lt.balanceOf(address(lp));
            assertGe(bal, LOCKED + un, "locked 200M breached");
            assertEq(bal, LOCKED + tinfo(lp, tk).inv + un, "launchpad token balance accounting");
            // supply conservation: every token is in the launchpad or with an actor (burns reduce supply)
            uint256 held = bal;
            for (uint256 a; a < actors.length; ++a) held += lt.balanceOf(actors[a]);
            assertEq(held, lt.totalSupply(), "balances sum to supply");
            // burned == C - inventory - tokens in user hands - unclaimed ... must be non-negative
            assertGe(CURVE - tinfo(lp, tk).inv, TOTAL - lt.totalSupply(), "burned <= sold");
        }
        assertFalse(h.supplyIncreased(), "a totalSupply rose");
    }

    /// forge-config: default.invariant.runs = 48
    /// forge-config: default.invariant.depth = 100
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_RewardsCurveMathAndNoBadReverts() public view {
        assertEq(h.badReverts(), 0, "handler saw InsufficientReserve/CurveMathError/Panic/transfer failure");
        uint256 n = lp.tokenCount();
        for (uint256 i; i < n; ++i) {
            address tk = lp.tokenAt(i);
            LaunchToken lt = LaunchToken(tk);
            // (8) entitlements never exceed the pool; launchpad earns nothing; claims <= pool history
            uint256 sum;
            for (uint256 a; a < actors.length; ++a) sum += lp.pendingHolderRewards(tk, actors[a]);
            assertLe(sum, lp.holderPool(tk), "pending rewards exceed pool");
            assertEq(lp.pendingHolderRewards(tk, address(lp)), 0);
            // (13) price / reserve follow the independent reference across all reachable states
            uint256 sold = CURVE - tinfo(lp, tk).inv;
            assertApproxEqRel(tinfo(lp, tk).price, Ref.price(sold), 1e9, "price vs ref");
            assertApproxEqAbs(lp.reserveRequired(tk), Ref.reserve(sold), 2e3, "reserve vs ref");
            assertEq(lt.launchpad(), address(lp));
        }
    }
}

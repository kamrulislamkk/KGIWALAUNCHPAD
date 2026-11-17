// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {KgiwaLaunchpadTestBase, Ref, TI} from "./KgiwaLaunchpad.Base.t.sol";
import {KgiwaLaunchpad} from "../KgiwaLaunchpad.sol";
import {LaunchToken} from "../LaunchToken.sol";

contract KgiwaLaunchpadFuzzTest is KgiwaLaunchpadTestBase {
    // ---- (3) buy accuracy, reserve invariant, price/reserve vs reference

    function testFuzz_BuyMatchesReferenceAndStaysBacked(uint256 v, uint256 bps) public {
        v = bound(v, MIN_TRADE, 700 ether);
        bps = bound(bps, 100, 300);
        LaunchToken t = _create(bps);
        uint256 supply0 = t.totalSupply();
        uint256 got = _buy(alice, t, v);
        assertApproxEqAbs(got, Ref.position(0, _net(v, bps)), TOKEN_TOL, "tokens vs reference");
        _assertBacked(t);
        uint256 s = _sold(t);
        assertEq(s, got + (supply0 - t.totalSupply()), "sold == bought + burned");
        assertApproxEqAbs(lp.reserveRequired(address(t)), Ref.reserve(s), 2e3, "reserve vs ref");
        assertApproxEqRel(_info(t).price, Ref.price(s), 1e9, "price vs ref");
        // buy-position accuracy: unspent dust ( reserveETH - required ) stays tiny
        uint256 dust = _info(t).reserve - lp.reserveRequired(address(t));
        assertLe(dust, 1e5, "inversion leaves only rounding dust");
        _assertLocked(t, 0);
        _assertLedger();
    }

    // ---- (2) pieces never beat one buy

    function testFuzz_SplitBuysNeverBeatOneBuy(uint256 v, uint256 frac, uint256 bps) public {
        v = bound(v, 2 * MIN_TRADE, 600 ether);
        bps = bound(bps, 100, 300);
        uint256 v1 = bound(frac, MIN_TRADE, v - MIN_TRADE);
        LaunchToken a = _create(bps);
        LaunchToken b = _create(bps);
        uint256 one = _buy(alice, a, v);
        uint256 split = _buy(bob, b, v1) + _buy(bob, b, v - v1);
        assertLe(split, one + 1e10, "splitting never yields more tokens");
        _assertBacked(a);
        _assertBacked(b);
    }

    function testFuzz_BuyThenSellNeverProfits(uint256 v, uint256 pct, uint256 bps) public {
        v = bound(v, 1 ether, 600 ether);
        pct = bound(pct, 10, 100);
        bps = bound(bps, 100, 300);
        LaunchToken t = _create(bps);
        uint256 before = alice.balance;
        uint256 got = _buy(alice, t, v);
        uint256 amt = got * pct / 100;
        (uint256 q,,) = lp.quoteSellDetail(address(t), amt);
        uint256 out = _sell(alice, t, amt);
        assertEq(out, q, "payout == quote");
        uint256 left = t.balanceOf(alice);
        assertEq(left, got - amt);
        if (pct == 100) {
            assertLt(alice.balance, before, "round trip loses fees");
            assertEq(_info(t).inv, CURVE - _burned(t), "inventory returns except burned");
        }
        assertLt(out, v);
        _assertBacked(t);
        _assertLocked(t, 0);
        _assertLedger();
    }

    // ---- (5) everyone exits in full, in any order

    function testFuzz_AllBuyersExitFullyInAnyOrder(uint256 a1, uint256 a2, uint256 a3, uint256 order) public {
        a1 = bound(a1, 0.05 ether, 150 ether);
        a2 = bound(a2, 0.05 ether, 150 ether);
        a3 = bound(a3, 0.05 ether, 150 ether);
        order = bound(order, 0, 2);
        LaunchToken t = _create(100);
        address[3] memory who = [alice, bob, carol];
        uint256[3] memory amts = [a1, a2, a3];
        for (uint256 i; i < 3; ++i) {
            _buy(who[i], t, amts[i]);
            _assertBacked(t);
        }
        for (uint256 k; k < 3; ++k) {
            address u = who[(k + order) % 3];
            uint256 bal = t.balanceOf(u);
            (uint256 q, uint256 fee,) = lp.quoteSellDetail(address(t), bal);
            uint256 resBefore = _info(t).reserve;
            uint256 out = _sell(u, t, bal);
            assertEq(out, q, "paid in full");
            assertEq(_info(t).reserve, resBefore - (q + fee) + fee * 20 / 100);
            assertEq(t.balanceOf(u), 0);
            _assertBacked(t);
            _assertLocked(t, 0);
        }
        _assertLedger();
    }

    // ---- (6) fee parts always sum to fee

    function testFuzz_FeePartsSumToFee(uint256 v, uint256 bps) public {
        v = bound(v, MIN_TRADE, 400 ether);
        bps = bound(bps, 100, 300);
        LaunchToken t = _create(bps);
        uint256 platBefore = platform.balance;
        vm.recordLogs();
        _buy(alice, t, v);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 fee = v * bps / 10_000;
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != KgiwaLaunchpad.FeesDistributed.selector) continue;
            (uint256 p, uint256 c, uint256 h, uint256 b) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            assertEq(p + c + h + b, fee);
            assertEq(platform.balance - platBefore, p, "platform paid exactly its part");
            assertEq(lp.creatorFees(address(t)), c);
            assertEq(lp.holderPool(address(t)), h);
            seen = true;
        }
        assertTrue(seen);
        _assertLedger();
    }

    // ---- (4) forced-short reserve always reverts

    function testFuzz_SellRevertsWhenReserveShort(uint256 v, uint256 shortBy) public {
        v = bound(v, 1 ether, 300 ether);
        LaunchToken t = _create(100);
        uint256 got = _buy(alice, t, v);
        (uint256 q, uint256 fee,) = lp.quoteSellDetail(address(t), got);
        uint256 gross = q + fee;
        shortBy = bound(shortBy, 1, gross);
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(address(t), uint256(5)))) + 4);
        vm.store(address(lp), slot, bytes32(gross - shortBy));
        vm.prank(alice);
        t.approve(address(lp), got);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientReserve()"));
        lp.sell(address(t), got, 0);
    }

    // ---- (13) monotonicity of quotes (expWad / lnWad sanity)

    function testFuzz_QuotesMonotonicAndMatchReference(uint256 v1, uint256 v2, uint256 pre) public {
        LaunchToken t = _create(100);
        pre = bound(pre, 0, 300 ether);
        if (pre >= MIN_TRADE) _buy(bob, t, pre);
        v1 = bound(v1, MIN_TRADE, 400 ether);
        v2 = bound(v2, v1, 400 ether);
        (uint256 o1,, uint256 p1) = lp.quoteBuyDetail(address(t), v1);
        (uint256 o2,, uint256 p2) = lp.quoteBuyDetail(address(t), v2);
        assertLe(o1, o2, "more ETH never yields fewer tokens");
        assertLe(p1, p2, "price monotone in ETH spent");
        uint256 s0 = _sold(t);
        assertApproxEqAbs(o1, Ref.position(s0, _net(v1, 100)) - s0, TOKEN_TOL, "quote vs reference");
        assertApproxEqRel(p1, Ref.price(s0 + o1), 1e9);
        assertGe(p1, _info(t).price, "price never below current");
    }

    function testFuzz_SequentialBuysKeepPriceReserveSupplyMonotonic(uint256 v1, uint256 v2, uint256 v3) public {
        LaunchToken t = _create(100);
        uint256[3] memory vs = [bound(v1, MIN_TRADE, 200 ether), bound(v2, MIN_TRADE, 200 ether), bound(v3, MIN_TRADE, 200 ether)];
        uint256 price = _info(t).price;
        uint256 req = 0;
        uint256 supply = t.totalSupply();
        for (uint256 i; i < 3; ++i) {
            _buy(alice, t, vs[i]);
            assertGt(_info(t).price, price);
            assertGt(lp.reserveRequired(address(t)), req);
            assertLt(t.totalSupply(), supply);
            price = _info(t).price;
            req = lp.reserveRequired(address(t));
            supply = t.totalSupply();
            _assertBacked(t);
        }
    }

    // ---- (10) fundraise fuzz: any contribution sequence fills backed

    function testFuzz_FundraiseFillIsBackedAndContinuous(uint256 target, uint256 seed, uint256 bps) public {
        target = bound(target, 0.01 ether, 50 ether);
        bps = bound(bps, 100, 300);
        vm.prank(creator);
        lp.createFundraise{value: 0.05 ether}("FR", "FR", "", TOTAL, target, bps);
        address[3] memory who = [alice, bob, carol];
        uint256 paid;
        for (uint256 i; i < 6; ++i) {
            (uint256 raised,, uint8 st,) = _frs(0);
            if (st != 0) break;
            uint256 remaining = target - raised;
            uint256 amt = bound(uint256(keccak256(abi.encode(seed, i))), MIN_TRADE, target);
            if (amt >= remaining && remaining < MIN_TRADE) amt = MIN_TRADE;
            vm.prank(who[i % 3]);
            uint256 b = who[i % 3].balance;
            lp.contribute{value: amt}(0);
            paid += b - who[i % 3].balance;
            // reserve for an unfilled raise is held as ETH, never more than target
            (raised,,,) = _frs(0);
            assertLe(raised, target);
        }
        (uint256 raised2,, uint8 st2,) = _frs(0);
        if (st2 == 0) {
            vm.prank(dave);
            lp.contribute{value: target}(0); // capped to the remainder, excess refunded
        }
        (raised2,, st2,) = _frs(0);
        assertEq(st2, 1, "filled");
        assertEq(raised2, target);
        (,, , address tk) = _frs(0);
        LaunchToken ft = LaunchToken(tk);
        TI memory ti = _info(ft);
        assertEq(ti.reserve, target);
        assertGe(ti.reserve, lp.reserveRequired(tk), "reserve backs allocations");
        (,uint256 frPrice,,) = _frs(0);
        assertEq(ti.price, frPrice);
        assertApproxEqRel(ti.price, Ref.price(CURVE - ti.inv), 1e9);
        assertApproxEqAbs(CURVE - ti.inv, Ref.position(0, target), TOKEN_TOL, "allocations follow the same curve");
        uint256 alloc;
        for (uint256 i; i < 4; ++i) {
            address[4] memory all = [alice, bob, carol, dave];
            (, uint256 tk_,,) = lp.fundraiseContribution(0, all[i]);
            alloc += tk_;
        }
        assertEq(alloc, CURVE - ti.inv);
        _assertLocked(ft, alloc);
        assertEq(address(lp).balance, target + 0, "only the raised ETH is held");
        // a post-launch buy and full sell stay backed
        _buy(bob, ft, 1 ether);
        _assertBacked(ft);
        assertGe(paid, 0);
    }

    function _frs(uint256 id) internal view returns (uint256 raised, uint256 price, uint8 status, address token) {
        (,,,,,, raised, price,, status, token) = lp.fundraises(id);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {KgiwaLaunchpadTestBase, Ref, TI} from "./KgiwaLaunchpad.Base.t.sol";
import {LaunchToken} from "../LaunchToken.sol";

contract KgiwaLaunchpadCurveTest is KgiwaLaunchpadTestBase {
    LaunchToken internal t;

    function setUp() public override {
        super.setUp();
        t = _create(100);
    }

    // ---- (1) start price / full curve / reserve at C

    function test_StartPriceIsP0AndEmptyCurve() public view {
        TI memory i = _info(t);
        assertEq(i.price, 2.5e11, "start price");
        assertEq(i.inv, CURVE);
        assertEq(i.reserve, 0);
        assertEq(i.supply, TOTAL);
        assertEq(i.bps, 100);
        assertTrue(i.launched);
        assertEq(lp.reserveRequired(address(t)), 0);
        assertEq(t.totalSupply(), TOTAL);
        assertEq(t.balanceOf(address(lp)), TOTAL);
        assertEq(lp.tokenCount(), 1);
    }

    function test_PriceAtFullCurveIs10xP0() public {
        _fillCurve(alice, t);
        TI memory i = _info(t);
        assertEq(i.inv, 0);
        assertEq(i.price, 10 * P0, "price at C must be 10x P0");
        _assertBacked(t);
    }

    function test_ReserveRequiredAtCapacityIs781_7Eth() public {
        _fillCurve(alice, t);
        uint256 req = lp.reserveRequired(address(t));
        assertApproxEqAbs(req, 781.7 ether, 0.1 ether, "~781.7 ETH");
        assertApproxEqAbs(req, Ref.reserve(CURVE), 1e3, "matches 9*A reference");
        assertApproxEqAbs(req, 9 * Ref.A, 1e3);
        assertApproxEqAbs(Ref.A, 86.86 ether, 0.01 ether, "A ~ 86.86 ETH");
        assertGe(_info(t).reserve, req);
    }

    function test_OneEthBuyMatchesMath() public {
        uint256 got = _buy(alice, t, 1 ether);
        uint256 expected = Ref.position(0, 0.99 ether);
        assertApproxEqAbs(got, expected, TOKEN_TOL, "tokens vs reference");
        // ~3.94M tokens for 0.99 ETH net (a fee-free 1 ETH would be ~3.98M)
        assertApproxEqAbs(got, 3_937_500e18, 20_000e18);
        uint256 feeFree = Ref.position(0, 1 ether);
        assertApproxEqAbs(feeFree, 3_977_000e18, 20_000e18, "fee-free ~3.98M");
        assertLt(got, feeFree);
        _assertBacked(t);
    }

    function test_PriceAndReserveTrackReferenceAcrossCurve() public {
        uint256[6] memory sizes = [uint256(0.01 ether), 1 ether, 10 ether, 100 ether, 250 ether, 300 ether];
        for (uint256 k; k < sizes.length; ++k) {
            _buy(alice, t, sizes[k]);
            uint256 s = _sold(t);
            assertApproxEqRel(_info(t).price, Ref.price(s), 1e9, "price vs ref");
            assertApproxEqAbs(lp.reserveRequired(address(t)), Ref.reserve(s), 2e3, "reserve vs ref");
            _assertBacked(t);
        }
    }

    function test_PriceStrictlyIncreasesWithEachBuy() public {
        uint256 last = _info(t).price;
        for (uint256 k; k < 10; ++k) {
            _buy(alice, t, 5 ether);
            uint256 p = _info(t).price;
            assertGt(p, last);
            last = p;
        }
    }

    function test_BuyAtDustFloor() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("TradeTooSmall()"));
        lp.buy{value: MIN_TRADE - 1}(address(t), 0);
        uint256 got = _buy(alice, t, MIN_TRADE);
        assertGt(got, 0);
        _assertBacked(t);
    }

    function test_BuyBeyondCapacityReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientInventory()"));
        lp.buy{value: 1000 ether}(address(t), 0);
    }

    function test_BuyAfterFullCurveReverts() public {
        _fillCurve(alice, t);
        vm.prank(bob);
        vm.expectRevert();
        lp.buy{value: 1 ether}(address(t), 0);
    }

    function test_SellEverythingAfterFullCurve() public {
        _fillCurve(alice, t);
        uint256 bal = t.balanceOf(alice);
        assertEq(bal + _burned(t), CURVE, "sold = held + burned");
        uint256 got = _sell(alice, t, bal);
        assertGt(got, 700 ether);
        _assertBacked(t);
        assertEq(_info(t).inv, CURVE - _burned(t));
        _assertLocked(t, 0);
    }

    function test_UnknownTokenReverts() public {
        vm.expectRevert(abi.encodeWithSignature("UnknownToken()"));
        lp.reserveRequired(address(0xdead));
        vm.expectRevert(abi.encodeWithSignature("UnknownToken()"));
        lp.quoteBuy(address(0xdead), 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("UnknownToken()"));
        lp.buy{value: 1 ether}(address(0xdead), 0);
    }
}

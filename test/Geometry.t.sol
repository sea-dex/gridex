// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Geometry} from "../src/strategy/Geometry.sol";
import {IGeometryErrors} from "../src/interfaces/IGeometryErrors.sol";
import {FullMath} from "../src/libraries/FullMath.sol";

contract GeometryTest is Test {
    Geometry public geometry;

    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;
    uint256 public constant RATIO_MULTIPLIER = 10 ** 18;

    function setUp() public {
        geometry = new Geometry(address(this));
    }

    function test_validateParams_askValid() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        geometry.validateParams(true, 1 ether, abi.encode(price0, ratio), 10);
    }

    function test_validateParams_bidValid() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = (9 * RATIO_MULTIPLIER) / 10; // 0.9
        geometry.validateParams(false, 1 ether, abi.encode(price0, ratio), 10);
    }

    function test_validateParams_revertInvalidCount() public {
        vm.expectRevert(IGeometryErrors.GeometryInvalidCount.selector);
        geometry.validateParams(true, 1 ether, abi.encode(PRICE_MULTIPLIER / 1000, RATIO_MULTIPLIER), 0);
    }

    function test_validateParams_revertAskRatioTooLow() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        vm.expectRevert(IGeometryErrors.GeometryAskRatioTooLow.selector);
        geometry.validateParams(true, 1 ether, abi.encode(price0, RATIO_MULTIPLIER), 10);
    }

    function test_validateParams_revertBidRatioTooHigh() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        vm.expectRevert(IGeometryErrors.GeometryBidRatioTooHigh.selector);
        geometry.validateParams(false, 1 ether, abi.encode(price0, RATIO_MULTIPLIER), 10);
    }

    function test_validateParams_revertAskZeroQuote() public {
        uint256 tinyPrice = 1;
        uint256 hugeRatio = type(uint256).max;
        vm.expectRevert(IGeometryErrors.GeometryAskZeroQuote.selector);
        geometry.validateParams(true, 1, abi.encode(tinyPrice, hugeRatio), 2);
    }

    function test_validateParams_revertBidZeroQuote() public {
        uint256 tinyPrice = 1;
        uint256 tinyRatio = 1; // quickly decays to 0
        vm.expectRevert(IGeometryErrors.GeometryBidZeroQuote.selector);
        geometry.validateParams(false, 1, abi.encode(tinyPrice, tinyRatio), 2);
    }

    function test_createGridStrategy_onlyGridEx() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("Unauthorized");
        geometry.createGridStrategy(true, 1, abi.encode(PRICE_MULTIPLIER / 1000, (11 * RATIO_MULTIPLIER) / 10));
    }

    function test_createGridStrategy_noDuplicate() public {
        geometry.createGridStrategy(true, 1, abi.encode(PRICE_MULTIPLIER / 1000, (11 * RATIO_MULTIPLIER) / 10));
        vm.expectRevert("Already exists");
        geometry.createGridStrategy(true, 1, abi.encode(PRICE_MULTIPLIER / 1000, (11 * RATIO_MULTIPLIER) / 10));
    }

    function test_getPriceAndReversePrice_ask() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        uint256 price1 = FullMath.mulDiv(price0, ratio, RATIO_MULTIPLIER);
        uint256 price2 = FullMath.mulDiv(price1, ratio, RATIO_MULTIPLIER);

        assertEq(geometry.getPrice(true, 1, 0), price0);
        assertEq(geometry.getPrice(true, 1, 1), price1);
        assertEq(geometry.getPrice(true, 1, 2), price2);

        assertEq(geometry.getReversePrice(true, 1, 2), price1);
        assertEq(geometry.getReversePrice(true, 1, 1), price0);
        assertEq(geometry.getReversePrice(true, 1, 0), FullMath.mulDiv(price0, RATIO_MULTIPLIER, ratio));
    }

    function test_getPriceAndReversePrice_bid() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = (9 * RATIO_MULTIPLIER) / 10; // 0.9
        geometry.createGridStrategy(false, 2, abi.encode(price0, ratio));

        uint256 price1 = FullMath.mulDiv(price0, ratio, RATIO_MULTIPLIER);
        uint256 price2 = FullMath.mulDiv(price1, ratio, RATIO_MULTIPLIER);

        assertEq(geometry.getPrice(false, 2, 0), price0);
        assertEq(geometry.getPrice(false, 2, 1), price1);
        assertEq(geometry.getPrice(false, 2, 2), price2);

        assertEq(geometry.getReversePrice(false, 2, 2), price1);
        assertEq(geometry.getReversePrice(false, 2, 1), price0);
        assertEq(geometry.getReversePrice(false, 2, 0), FullMath.mulDiv(price0, RATIO_MULTIPLIER, ratio));
    }
}

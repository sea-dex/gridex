// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Factory} from "../src/Factory.sol";
import {IPair} from "../src/interfaces/IPair.sol";
import {IFactory} from "../src/interfaces/IFactory.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";
import {Currency} from "../src/libraries/Currency.sol";

contract FactoryTest is Test {
    Factory public factory;
    SEA public sea;
    USDC public usdc;
    WETH public weth;

    function setUp() public {
        factory = new Factory();
        sea = new SEA();
        usdc = new USDC();
        weth = new WETH();
    
        factory.setQuoteToken(address(weth), 100);
        factory.setQuoteToken(address(usdc), 200);
    }

    function test_createPair() public {
        vm.expectEmit(true, true, true, false);
        emit IFactory.PairCreated(address(weth), address(usdc), 500, address(0));
        address wethUSDC500 = factory.createPair(address(weth), address(usdc), 500);
        assertEq(IPair(wethUSDC500).factory(), address(factory));
        assertEq(IPair(wethUSDC500).fee(), 500);
        assertEq(Currency.unwrap(IPair(wethUSDC500).baseToken()), address(weth));
        assertEq(Currency.unwrap(IPair(wethUSDC500).quoteToken()), address(usdc));

        vm.expectEmit(true, true, true, false);
        emit IFactory.PairCreated(address(weth), address(usdc), 100, address(0));
        address wethUSDC100 = factory.createPair(address(usdc), address(weth), 100);
        assertEq(IPair(wethUSDC100).factory(), address(factory));
        assertEq(IPair(wethUSDC100).fee(), 100);
        assertEq(Currency.unwrap(IPair(wethUSDC100).baseToken()), address(weth));
        assertEq(Currency.unwrap(IPair(wethUSDC100).quoteToken()), address(usdc));

        vm.expectEmit(true, true, true, false);
        emit IFactory.PairCreated(address(sea), address(weth), 2000, address(0));
        address seaETH = factory.createPair(address(weth), address(sea), 2000);
        assertEq(IPair(seaETH).factory(), address(factory));
        assertEq(IPair(seaETH).fee(), 2000);
        assertEq(Currency.unwrap(IPair(seaETH).baseToken()), address(sea));
        assertEq(Currency.unwrap(IPair(seaETH).quoteToken()), address(weth));
        // counter.increment();
        // assertEq(counter.number(), 1);
    }

    function test_createPair_fails() public {
        factory.createPair(address(weth), address(usdc), 500);

        // pair already exists
        vm.expectRevert();
        factory.createPair(address(weth), address(usdc), 500);

        // pair already exists
        vm.expectRevert();
        factory.createPair(address(usdc), address(weth), 500);

        // fee rate not exist
        vm.expectRevert();
        factory.createPair(address(sea), address(usdc), 3000);
    }

    function test_setQuoteToken_failsNoauth() public {
        address other = 0x1111111111111111111111111111111111111111;
        vm.startPrank(other);
        vm.expectRevert();
        factory.setQuoteToken(address(sea), 50);
        vm.stopPrank();
    }

    function test_enableFeeAmount() public {
        vm.expectEmit(true, true, false, false);
        emit IFactory.FeeAmountEnabled(3000, 4);
        factory.enableFeeAmount(3000, 4);


        vm.expectEmit(true, true, false, false);
        emit IFactory.FeeAmountEnabled(3000, 10);
        factory.enableFeeAmount(3000, 10);
    }

    function test_enableFeeAmount_failsInvalid() public {
        vm.expectRevert();
        factory.enableFeeAmount(2000, 11);

        vm.expectRevert();
        factory.enableFeeAmount(2000, 3);
    }

    function test_enableFeeAmount_failsNoauth() public {
        address other = 0x1111111111111111111111111111111111111111;
        vm.startPrank(other);
        vm.expectRevert();
        factory.enableFeeAmount(2000, 10);
        vm.stopPrank();
    }

    function test_SetOwner() public {
        address other = 0x1111111111111111111111111111111111111111;
        vm.expectEmit(false, true, false, false);
        emit IFactory.OwnerChanged(address(0), other);
        factory.setOwner(other);

        assertEq(factory.owner(), other);
    }
}

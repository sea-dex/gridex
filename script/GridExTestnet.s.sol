// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {GridEx} from "../src/GridEx.sol";

import {WETH} from "../test/utils/WETH.sol";
import {USDC} from "../test/utils/USDC.sol";

contract GridExScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        WETH weth = new WETH();
        USDC usdc = new USDC();
        GridEx gridEx = new GridEx(address(weth), address(usdc), address(0));
        gridEx;
        vm.stopBroadcast();
    }
}

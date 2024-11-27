// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {GridEx} from "../src/GridEx.sol";
import {Router} from "../src/Router.sol";

contract GridExScript is Script {
    function setUp() public {}

    function run(address weth_, address usd_) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        GridEx gridEx = new GridEx(weth_, usd_);
        Router router = new Router(address(gridEx));
        router;
        vm.stopBroadcast();
    }
}

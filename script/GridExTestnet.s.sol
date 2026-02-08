// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Script} from "forge-std/Script.sol";

import {GridEx} from "../src/GridEx.sol";
import {Vault} from "../src/Vault.sol";

import {WETH} from "../test/utils/WETH.sol";
import {USDC} from "../test/utils/USDC.sol";

contract GridExScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        WETH weth = new WETH();
        USDC usdc = new USDC();
        Vault vault = new Vault(deployer);
        GridEx gridEx = new GridEx(deployer, address(vault));
        gridEx.initialize(address(weth), address(usdc));
        vm.stopBroadcast();
    }
}

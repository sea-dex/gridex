// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

// import {Vault} from "../src/Vault.sol";
// import {Linear} from "../src/strategy/Linear.sol";
import {GridEx} from "../src/GridEx.sol";

contract GridExScript is Script {
    address constant WETH_ = address(0xb15BDeAAb6DA2717F183C4eC02779D394e998e91);
    address constant USD_ = address(0xe8D9fF1263C9d4457CA3489CB1D30040f00CA1b2);
    // address constant linear = address();
    address constant VAULT = address(0x37E4B20992f686425E28941677eDeF00CEcC3f98);

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        // new Linear();
        // Vault vault = new Vault();
        GridEx gridEx = new GridEx(WETH_, USD_, address(VAULT));
        gridEx;
        vm.stopBroadcast();
    }
}

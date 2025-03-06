// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Owned} from "solmate/auth/Owned.sol";

contract Vault is Owned {
    constructor() Owned(msg.sender) {}
}

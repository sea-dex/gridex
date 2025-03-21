// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import "./ERC20.sol";

contract USDC is ERC20 {
    address public admin;

    constructor() ERC20("USDC", "USDC", 6) {
        admin = msg.sender;
        _mint(msg.sender, 1000000000000000);
    }

    function mint(address to, uint256 amount) external virtual {
        require(msg.sender == admin);

        _mint(to, amount);
    }
}

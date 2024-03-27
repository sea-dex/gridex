// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import "./ERC20.sol";

contract USDC is ERC20 {

    address public admin;

    constructor() ERC20("SEA", "SEA", 18) {
        admin = msg.sender;
        _mint(msg.sender, 10000000000000000000000000);
    }

    function mint(address to, uint256 amount) external virtual {
        require(msg.sender == admin);

        _mint(to, amount);
    }
}

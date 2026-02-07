// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.33;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./ERC20.sol";

contract SEA is ERC20 {
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

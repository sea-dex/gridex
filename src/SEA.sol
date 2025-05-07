// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract SEA is ERC20, Owned {
    uint256 public constant MAX_SUPPLY = 10 ** 9;

    uint256 public constant vaultProportion = 30; // 15%
    uint256 public constant developerProportion = 30; // 15%
    uint256 public constant managerProportion = 50; // 25%

    /// SEA vault address
    address public vault;
    /// developer reward address
    address public developer;
    /// community manage reward address
    address public manager;

    /// @notice The timestamp of address last claimed
    mapping(address => uint256) lastClaimAt;

    constructor(
        address[] memory addrs
    ) ERC20("SEA", "SEA", 18) Owned(msg.sender) {
        vault = addrs[0];
        developer = addrs[1];
        manager = addrs[2];
    }

    /// claim user's reward
    function claim(
        address to,
        uint256 amount,
        uint256 ts,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        require(amount + ((amount * 55) / 100) < MAX_SUPPLY, "S0");
        require(ts < block.timestamp + 60, "S1");
        require(ts > block.timestamp - 60, "S2");
        require(lastClaimAt[to] + 600 < block.timestamp, "S3");

        verifySignature(to, amount, ts, _v, _r, _s);
        //         bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        // bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, _hashedMessage));

        _mint(to, amount);
        _mint(vault, (amount * vaultProportion) / 100);
        _mint(developer, (amount * developerProportion) / 100);
        _mint(manager, (amount * managerProportion) / 100);

        lastClaimAt[to] = block.timestamp;
    }

    function verifySignature(
        address to,
        uint256 amount,
        uint256 ts,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) private view {
        bytes32 hash = keccak256(
            abi.encode(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encodePacked(block.chainid, to, amount, ts))
            )
        );
        address signer = ecrecover(hash, _v, _r, _s);

        require(signer == owner, "S4");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title Create2Deployer
/// @notice A factory contract for deterministic deployment using CREATE2
/// @dev This contract allows deploying contracts to the same address across different chains
contract Create2Deployer {
    /// @notice Emitted when a contract is deployed
    /// @param deployed The address of the deployed contract
    /// @param salt The salt used for deployment
    event Deployed(address indexed deployed, bytes32 indexed salt);

    /// @notice Deploy a contract using CREATE2
    /// @param salt The salt for deterministic address generation
    /// @param bytecode The contract bytecode including constructor arguments
    /// @return deployed The address of the deployed contract
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address deployed) {
        assembly {
            deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(deployed) { revert(0, 0) }
        }
        emit Deployed(deployed, salt);
    }

    /// @notice Compute the address of a contract deployed with CREATE2
    /// @param salt The salt for deterministic address generation
    /// @param bytecodeHash The keccak256 hash of the contract bytecode
    /// @return The computed address
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
    }

    /// @notice Compute the address of a contract deployed with CREATE2 using bytecode
    /// @param salt The salt for deterministic address generation
    /// @param bytecode The contract bytecode including constructor arguments
    /// @return The computed address
    function computeAddressFromBytecode(bytes32 salt, bytes memory bytecode) external view returns (address) {
        bytes32 bytecodeHash = keccak256(bytecode);
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
    }
}

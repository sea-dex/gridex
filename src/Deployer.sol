// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./interfaces/IPairDeployer.sol";

import "./Pair.sol";

contract Deployer is IPairDeployer {
    struct Parameters {
        address factory;
        address base;
        address quote;
        uint24 fee;
        uint8 feeProtocol;
    }

    /// @inheritdoc IPairDeployer
    Parameters public override parameters;

    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    /// @param factory The contract address of the Uniswap V3 factory
    /// @param base The first token of the pool by address sort order
    /// @param quote The second token of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    function deploy(
        address factory,
        address base,
        address quote,
        uint24 fee,
        uint8 feeProtocol
    ) internal returns (address pool) {
        parameters = Parameters({
            factory: factory,
            base: base,
            quote: quote,
            fee: fee,
            feeProtocol: feeProtocol
        });
        pool = address(
            new Pair{salt: keccak256(abi.encode(base, quote, fee))}()
        );
        delete parameters;
    }
}

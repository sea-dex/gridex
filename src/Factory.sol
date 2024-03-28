// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./interfaces/IFactory.sol";

import "./Pair.sol";
import "./Deployer.sol";
import "./NoDelegateCall.sol";

/// @title Canonical factory
/// @notice Deploys pairs and manages ownership and control over pool protocol fees
contract Factory is IFactory, Deployer, NoDelegateCall {
    /// @inheritdoc IFactory
    address public override owner;

    /// @inheritdoc IFactory
    mapping(address => uint8) public override quotableTokens;
    /// @inheritdoc IFactory
    mapping(uint24 => uint8) public override feeAmount;
    /// @inheritdoc IFactory
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPair;

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        feeAmount[100] = 6;
        feeAmount[200] = 6;
        feeAmount[500] = 6;
        feeAmount[2000] = 6;
        feeAmount[10000] = 6;

        quotableTokens[address(0)] = 100;
    }

    /// @inheritdoc IFactory
    function createPair(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pair) {
        require(tokenA != tokenB);
        require(tokenA != address(0));
        require(tokenB != address(0));

        uint8 p1 = quotableTokens[tokenA];
        uint8 p2 = quotableTokens[tokenB];
        require(p1 > 0 || p2 > 0);
        address token0;
        address token1;
        if (p1 > p2) {
            (token0, token1) = (tokenB, tokenA);
        } else if (p1 < p2) {
            (token0, token1) = (tokenA, tokenB);
        } else {
            (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        }
        uint8 feeProtocol = feeAmount[fee];
        require(feeProtocol != 0);

        require(getPair[token0][token1][fee] == address(0));
        pair = deploy(address(this), token0, token1, fee, feeProtocol);
        getPair[token0][token1][fee] = pair;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPair[token1][token0][fee] = pair;
        emit PairCreated(token0, token1, fee, pair);
    }

    /// @inheritdoc IFactory
    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @inheritdoc IFactory
    function setQuoteToken(address token, uint8 priority) external override {
        require(msg.sender == owner);
        require(priority > 0);
        emit QuotableTokenEnabled(token, priority);
        quotableTokens[token] = priority;
    }

    /// @inheritdoc IFactory
    function enableFeeAmount(uint24 fee, uint8 feeProtocol) public override {
        require(msg.sender == owner);
        require(fee < 1000000);
        require((feeProtocol >= 4 && feeProtocol <= 10));

        feeAmount[fee] = feeProtocol;

        emit FeeAmountEnabled(fee, feeProtocol);
    }
}

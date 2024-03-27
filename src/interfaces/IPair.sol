// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "../libraries/Currency.sol";
import "./IPairEvents.sol";

interface IPair is IPairEvents {
    //////////////////////////////// Errors ////////////////////////////////

    /// @notice Thrown when param invalid
    error InvalidParam();

    /// @notice Thrown when grid buy price0 or sell price0 invalid
    error InvalidGridPrice();

    /// @notice Thrown when grid quote amount invalid
    error InvalidGridAmount();

    /// @notice Thrown when grid order base amount great than uint96.MAX
    error ExceedMaxAmount();

    /// @notice Thrown when no grid order
    error ZeroGridOrderCount();

    /// @notice Thrown when buy price less than 0 or sell prive overflow
    error InvalidGapPrice();

    /// @notice Thrown when base token not enough
    error NotEnoughBaseToken();

    /// @notice Thrown when quote token not enough
    error NotEnoughQuoteToken();

    /// @notice Thrown when not enough to be filled
    error NotEnoughToFill();

    /// @notice Thrown when order is NOT grid order
    error NotGridOrder();

    /// @notice Thrown when order is NOT limit order
    error NotLimitOrder();

    /// @notice Thrown when msg.sender is NOT order owner
    error NotOrderOwner();

    /// @notice Thrown when max ask orderId reached
    error ExceedMaxAskOrder();

    /// @notice Thrown when max bid orderId reached
    error ExceedMaxBidOrder();


    /// @notice Thrown when calculate quote amount is 0
    error ZeroQuoteAmt();

    /// @notice Thrown when calculate quote amount exceed uint96.max
    error ExceedQuoteAmt();

    /// @notice Thrown when calculate base amount is 0
    error ZeroBaseAmt();

    /// @notice Thrown when calculate base amount exceed uint96.max
    error ExceedBaseAmt();

    /// @notice Thrown when gridId invalid
    error InvalidGridId();

    //////////////////////////////// Immutables ////////////////////////////////

    /// @notice The contract that deployed the pool, which must adhere to the IUniswapV3Factory interface
    /// @return The contract address
    function factory() external view returns (address);

    /// @notice The base token of the pair
    /// @return The token contract address
    function baseToken() external view returns (Currency);

    /// @notice The quote token of the pair
    /// @return The token contract address
    function quoteToken() external view returns (Currency);

    /// @notice The pool's fee in hundredths of a bip, i.e. 1e-6
    /// @return The fee
    function fee() external view returns (uint24);

    //////////////////////////////// States ////////////////////////////////

    /// @notice The 0th storage slot in the pool stores many values, and is exposed as a single method to save gas
    /// when accessed externally.
    /// @return fee trading fee
    /// feeProtocol The protocol fee for both tokens of the pool.
    /// Encoded as two 4 bit values, where the protocol fee of token1 is shifted 4 bits and the protocol fee of token0
    /// is the lower 4 bits. Used as the denominator of a fraction of the swap fee, e.g. 4 means 1/4th of the swap fee.
    /// unlocked Whether the pool is currently locked to reentrancy
    function slot0()
        external
        view
        returns (uint24 fee, uint8 feeProtocol, bool unlocked);

    /// @notice The amounts of quote that are owed to the protocol
    /// @dev Protocol fees will never exceed uint256 max, all fee is quote token
    function protocolFees() external view returns (uint256 quote);

    /// @notice Set pair protocol fee
    function setFeeProtocol(uint8 _feeProtocol) external;

    /// @notice Collect the protocol fee accrued to the pool
    /// @param recipient The address to which collected protocol fees should be sent
    /// @param amount The maximum amount
    /// @return The protocol fee collected
    function collectProtocol(
        address recipient,
        uint256 amount
    ) external returns (uint256);
}

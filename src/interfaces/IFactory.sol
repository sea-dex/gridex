// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title The interface for the Factory
/// @notice The Factory facilitates creation of pairs and control over the protocol fees
interface IFactory {
    /// @notice Emitted when the owner of the factory is changed
    /// @param oldOwner The owner before the owner was changed
    /// @param newOwner The owner after the owner was changed
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    /// @notice Emitted when a pair is created
    /// @param base The base token of the pair
    /// @param quote The quote token of the pair
    /// @param fee The fee collected upon every trade in the pair, denominated in hundredths of a bip
    /// @param pair The address of the created pair
    event PairCreated(
        address indexed base,
        address indexed quote,
        uint24 indexed fee,
        address pair
    );

    /// @notice Emitted when a new fee amount is enabled for pair creation via the factory
    /// @param fee The enabled fee, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks for pairs created with the given fee
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);


    /// @notice Emitted when a new token was set quotable
    /// @param token The enabled quote token
    /// @param priority The priority of quotable token
    event QuotableTokenEnabled(address indexed token, uint8 priority);

    /// @notice Returns the current owner of the factory
    /// @dev Can be changed by the current owner via setOwner
    /// @return The address of the factory owner
    function owner() external view returns (address);


    /// @notice Returns the priority of the quote token
    /// @dev Only quotable token can be pair's quote token, if both token is quotable, the priority higher is quote.
    /// quote token can not be removed
    /// @param token quote token
    /// @return The priority of the token
    function quotableTokens(address token) external view returns (uint8);

    /// @notice Returns the feeProtocol for a given fee amount, if enabled, or 0 if not enabled
    /// @dev A fee amount can never be removed, so this value should be hard coded or cached in the calling context
    /// @param fee The enabled fee, denominated in hundredths of a bip. Returns 0 in case of unenabled fee
    /// @return The default feeProtocol of this fee rate
    function feeAmount(uint24 fee) external view returns (uint8);

    /// @notice Returns the pair address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param fee The fee collected upon every swap in the pair, denominated in hundredths of a bip
    /// @return pair The pair address
    function getPair(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pair);

    /// @notice Creates a pair for the given two tokens and fee
    /// @param base One of the two tokens in the desired pair
    /// @param quote The other of the two tokens in the desired pair
    /// @param fee The desired fee for the pair
    /// @dev base and quote may be passed in order: base/quote. 
    /// The call will revert if the pair already exists, the fee is invalid, or the token arguments
    /// are invalid.
    /// @return pair The address of the newly created pair
    function createPair(
        address base,
        address quote,
        uint24 fee
    ) external returns (address pair);

    /// @notice Updates the owner of the factory
    /// @dev Must be called by the current owner
    /// @param _owner The new owner of the factory
    function setOwner(address _owner) external;

    /// @notice set or update the quote token priority
    /// @dev Must be called by the current owner
    /// @param token The quotable token
    /// @param priority The priority of the quotable token
    function setQuoteToken(address token, uint8 priority) external;
    
    /// @notice Enables a fee amount
    /// @dev Fee amounts may never be removed once enabled
    /// @param fee The fee amount to enable, denominated in hundredths of a bip (i.e. 1e-6)
    function enableFeeAmount(uint24 fee, uint8 feeProtocol) external;
}

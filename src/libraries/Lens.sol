// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IOrderErrors} from "../interfaces/IOrderErrors.sol";
import {FullMath} from "./FullMath.sol";

/// @title Lens
/// @author GridEx Protocol
/// @notice Library for calculating base/quote amounts for given prices
/// @dev Contains functions for price calculations and fee computations in grid orders
library Lens {
    /// @notice Price multiplier for fixed-point arithmetic (10^36)
    /// @dev All prices are scaled by this factor for precision
    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;

    /// @notice Calculate quote amount from base amount and price
    /// @dev Uses FullMath for 512-bit precision to prevent overflow
    /// @param baseAmt The base token amount
    /// @param price The price (scaled by PRICE_MULTIPLIER)
    /// @param roundUp Whether to round up the result
    /// @return The calculated quote amount
    function calcQuoteAmount(uint128 baseAmt, uint256 price, bool roundUp) public pure returns (uint128) {
        uint256 amt = roundUp
            ? FullMath.mulDivRoundingUp(uint256(baseAmt), uint256(price), PRICE_MULTIPLIER)
            : FullMath.mulDiv(uint256(baseAmt), uint256(price), PRICE_MULTIPLIER);

        if (amt == 0) {
            revert IOrderErrors.ZeroQuoteAmt();
        }
        if (amt >= uint256(type(uint128).max)) {
            revert IOrderErrors.ExceedQuoteAmt();
        }
        // casting to 'uint128' is safe because has verified above
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(amt);
    }

    /// @notice Calculate base and quote token amounts needed to place a grid order
    /// @dev Iterates through bid orders to calculate total quote amount needed
    /// @param baseAmt The base token amount per order
    /// @param bidPrice The starting bid price
    /// @param bidGap The price gap between bid orders
    /// @param askCount The number of ask orders
    /// @param bidCount The number of bid orders
    /// @return The total base amount needed
    /// @return The total quote amount needed
    function calcGridAmount(uint128 baseAmt, uint256 bidPrice, uint256 bidGap, uint32 askCount, uint32 bidCount)
        public
        pure
        returns (uint128, uint128)
    {
        uint128 quoteAmt;

        for (uint256 i = 0; i < bidCount; ++i) {
            uint128 amt = calcQuoteAmount(baseAmt, bidPrice, false);
            quoteAmt += amt;
            bidPrice -= bidGap;
        }

        return (baseAmt * askCount, quoteAmt);
    }

    /// @notice Calculate base amount from quote amount and price
    /// @dev Uses FullMath for 512-bit precision to prevent overflow
    /// @param quoteAmt The quote token amount
    /// @param price The price (scaled by PRICE_MULTIPLIER)
    /// @param roundUp Whether to round up the result
    /// @return The calculated base amount
    function calcBaseAmount(uint128 quoteAmt, uint256 price, bool roundUp) public pure returns (uint256) {
        uint256 amt = roundUp
            ? FullMath.mulDivRoundingUp(uint256(quoteAmt), Lens.PRICE_MULTIPLIER, uint256(price))
            : FullMath.mulDiv(uint256(quoteAmt), Lens.PRICE_MULTIPLIER, uint256(price));

        if (amt == 0) {
            revert IOrderErrors.ZeroBaseAmt();
        }
        if (amt >= uint256(type(uint128).max)) {
            revert IOrderErrors.ExceedBaseAmt();
        }
        return amt;
    }

    /// @notice Calculate quote token amount needed to fill an ask order
    /// @dev Taker pays quoteVol + fee to receive baseAmt
    /// @param price The fill price (scaled by PRICE_MULTIPLIER)
    /// @param baseAmt The base token amount to fill
    /// @param feebps The fee in basis points (1 bps = 0.01%)
    /// @return quoteVol The quote volume (rounded up)
    /// @return fee The total fee (LP fee + protocol fee)
    function calcAskOrderQuoteAmount(uint256 price, uint128 baseAmt, uint32 feebps)
        public
        pure
        returns (uint128 quoteVol, uint128 fee)
    {
        // quote volume taker will pay: quoteVol = filled * price
        quoteVol = calcQuoteAmount(baseAmt, price, true);
        fee = uint128((uint256(quoteVol) * uint256(feebps)) / 1000000);
        return (quoteVol, fee);
    }

    /// @notice Calculate quote token amount received by filling a bid order
    /// @dev Taker receives filledVol - fee for selling baseAmt
    /// @param price The fill price (scaled by PRICE_MULTIPLIER)
    /// @param baseAmt The base token amount to fill
    /// @param feebps The fee in basis points (1 bps = 0.01%)
    /// @return filledVol The quote volume (rounded down)
    /// @return fee The total fee (LP fee + protocol fee)
    function calcBidOrderQuoteAmount(uint256 price, uint128 baseAmt, uint32 feebps)
        public
        pure
        returns (uint128 filledVol, uint128 fee)
    {
        filledVol = calcQuoteAmount(baseAmt, price, false);
        fee = uint128((uint256(filledVol) * uint256(feebps)) / 1000000);
        return (filledVol, fee);
    }

    /// @notice Calculate LP fee and protocol fee from total volume
    /// @dev Protocol fee is 25% of total fee, LP fee is 75%
    /// @param vol The quote volume
    /// @param bps The fee in basis points
    /// @return lpFee The LP fee portion
    /// @return protocolFee The protocol fee portion
    function calculateFees(uint128 vol, uint32 bps) public pure returns (uint128 lpFee, uint128 protocolFee) {
        unchecked {
            uint128 fee = uint128((uint256(vol) * uint256(bps)) / 1000000);
            protocolFee = fee >> 2;
            lpFee = fee - protocolFee;
        }
    }

    /// @notice Calculate fees for oneshot orders (75% protocol, 25% maker)
    /// @dev For oneshot orders, protocol gets 75% and maker gets 25% of the fee
    /// @param vol The quote volume
    /// @param bps The fee in basis points
    /// @return lpFee The maker fee portion (25%)
    /// @return protocolFee The protocol fee portion (75%)
    function calculateOneshotFee(uint128 vol, uint32 bps) public pure returns (uint128 lpFee, uint128 protocolFee) {
        unchecked {
            uint128 fee = uint128((uint256(vol) * uint256(bps)) / 1000000);
            lpFee = fee >> 2;
            protocolFee = fee - lpFee;
        }
    }
}

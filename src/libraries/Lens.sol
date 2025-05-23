// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IOrderErrors} from "../interfaces/IOrderErrors.sol";
import {FullMath} from "./FullMath.sol";

/// @title Library for calculate base/quote for given price and amount
/// @notice Contains functions for calculate base/quote amount for given price and amount
library Lens {
    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;

    /// @dev calculate quote amount with baseAmt and price
    /// @param baseAmt base token amount
    /// @param price price
    /// @param roundUp whether quote amount round up or not
    /// @return amt amount
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
        return uint128(amt);
    }

    /// @dev calculate base token and quote token needed to place grid order
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

    /// calculate how many base can be filled with quoteAmt
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

    /// @dev how many quote token needed for fill ask order
    /// @param price filled price
    /// @param baseAmt filled base token amount
    /// @param feebps fee bps
    /// @return quoteVol filled quote volume, round up. taker should pay quoteVol + fee
    /// @return fee filled fee (LP fee + protocol fee)
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

    /// @dev how many quote token got by fill bid order
    /// @param price filled price
    /// @param baseAmt filled base token amount
    /// @param feebps fee bps
    /// @return filledVol filled quote volume, round down. taker will get filledVol - fee
    /// @return fee filled fee (LP fee + protocol fee)
    function calcBidOrderQuoteAmount(uint256 price, uint128 baseAmt, uint32 feebps)
        public
        pure
        returns (uint128 filledVol, uint128 fee)
    {
        filledVol = calcQuoteAmount(baseAmt, price, false);
        fee = uint128((uint256(filledVol) * uint256(feebps)) / 1000000);
        return (filledVol, fee);
    }

    function calculateFees(uint128 vol, uint32 bps) public pure returns (uint128 lpFee, uint128 protocolFee) {
        unchecked {
            uint128 fee = uint128((uint256(vol) * uint256(bps)) / 1000000);
            protocolFee = fee * 60 / 100;
            lpFee = fee - protocolFee;
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {IOrderErrors} from "./interfaces/IOrderErrors.sol";
import {FullMath} from "./libraries/FullMath.sol";

contract Lens {
    uint256 public constant PRICE_MULTIPLIER = 10 ** 29;

    /// calculate how many quote can be filled with baseAmt
    function calcQuoteAmount(
        uint128 baseAmt,
        uint160 price,
        bool roundUp
    ) public pure returns (uint128) {
        uint256 amt = roundUp
            ? FullMath.mulDivRoundingUp(
                uint256(baseAmt),
                uint256(price),
                PRICE_MULTIPLIER
            )
            : FullMath.mulDiv(
                uint256(baseAmt),
                uint256(price),
                PRICE_MULTIPLIER
            );

        if (amt == 0) {
            revert IOrderErrors.ZeroQuoteAmt();
        }
        if (amt >= uint256(type(uint128).max)) {
            revert IOrderErrors.ExceedQuoteAmt();
        }
        return uint128(amt);
    }

    function calcGridAmount(
        uint128 baseAmt,
        uint160 bidPrice,
        uint160 bidGap,
        uint32 askCount,
        uint32 bidCount
    ) public pure returns (uint128, uint128) {
        uint128 quoteAmt;

        for (uint256 i = 0; i < bidCount; ++i) {
            uint128 amt = calcQuoteAmount(baseAmt, bidPrice, false);
            quoteAmt += amt;
            bidPrice -= bidGap;
        }

        return (baseAmt * askCount, quoteAmt);
    }

    // how many quote token needed for fill ask order
    function calcQuoteAmountForAskOrder(
        uint160 price,
        uint128 baseAmt,
        uint32 feebps
    ) public pure returns (uint128, uint128) {
        // quote volume taker will pay: quoteVol = filled * price
        uint128 quoteVol = calcQuoteAmount(baseAmt, price, true);
        uint128 fee = uint128((uint256(quoteVol) * uint256(feebps)) / 1000000);
        return (quoteVol, fee);
    }

    // how many quote token got by fill bid order
    function calcQuoteAmountByBidOrder(
        uint160 price,
        uint128 baseAmt,
        uint32 feebps
    ) public pure returns (uint128, uint128) {
        uint128 filledVol = calcQuoteAmount(baseAmt, price, false);
        uint128 fee = uint128((uint256(filledVol) * uint256(feebps)) / 1000000);
        return (filledVol, fee);
    }
}

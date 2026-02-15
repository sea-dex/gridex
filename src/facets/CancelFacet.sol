// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../interfaces/IGridOrder.sol";
import {IOrderErrors} from "../interfaces/IOrderErrors.sol";
import {IOrderEvents} from "../interfaces/IOrderEvents.sol";
import {IPair} from "../interfaces/IPair.sol";
import {IWETH} from "../interfaces/IWETH.sol";

import {Currency, CurrencyLibrary} from "../libraries/Currency.sol";
import {GridOrder} from "../libraries/GridOrder.sol";
import {GridExStorage} from "../libraries/GridExStorage.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @title CancelFacet
/// @author GridEx Protocol
/// @notice Cancel and withdraw operations for grid orders
/// @dev Delegatecalled by GridExRouter. Guards applied at Router level.
contract CancelFacet is IOrderEvents {
    using CurrencyLibrary for Currency;
    using GridOrder for GridOrder.GridState;
    using SafeTransferLib for ERC20;

    event WithdrawProfit(uint128 gridId, Currency quote, address to, uint256 amt);

    error ETHTransferFailed();
    error NotWETH();

    // ─── Asset helpers ───────────────────────────────────────────────

    // forge-lint: disable-next-line(mixed-case-function)
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        if (!success) revert ETHTransferFailed();
    }

    function _transferAssetTo(Currency token, address addr, uint256 amount, uint32 flag) internal {
        if (flag == 0) {
            token.transfer(addr, amount);
        } else {
            address weth = GridExStorage.layout().weth;
            if (Currency.unwrap(token) != weth) revert NotWETH();
            IWETH(weth).withdraw(amount);
            _safeTransferETH(addr, amount);
        }
    }

    // ─── Cancel operations ───────────────────────────────────────────

    /// @notice Cancel an entire grid and withdraw all remaining tokens
    /// @param recipient The address to receive the withdrawn tokens
    /// @param gridId The grid ID to cancel
    /// @param flag Bit flags: 1 = base to ETH, 2 = quote to ETH
    function cancelGrid(address recipient, uint128 gridId, uint32 flag) external {
        GridExStorage.Layout storage l = GridExStorage.layout();
        (uint64 pairId, uint256 baseAmt, uint256 quoteAmt) = l.gridState.cancelGrid(msg.sender, gridId);
        IPair.Pair memory pair = l.getPairById[pairId];
        if (baseAmt > 0) {
            _transferAssetTo(pair.base, recipient, baseAmt, flag & 0x1);
        }
        if (quoteAmt > 0) {
            _transferAssetTo(pair.quote, recipient, quoteAmt, flag & 0x2);
        }

        emit CancelWholeGrid(msg.sender, gridId);
    }

    /// @notice Cancel a range of consecutive grid orders
    /// @param recipient The address to receive the withdrawn tokens
    /// @param startGridOrderId The first grid order ID to cancel
    /// @param howmany The number of consecutive orders to cancel
    /// @param flag Bit flags: 1 = base to ETH, 2 = quote to ETH
    function cancelGridOrders(address recipient, uint256 startGridOrderId, uint32 howmany, uint32 flag) external {
        uint256[] memory idList = new uint256[](howmany);
        (uint128 gridId,) = GridOrder.extractGridIdOrderId(startGridOrderId);
        for (uint256 i; i < howmany;) {
            idList[i] = startGridOrderId + i;
            unchecked {
                ++i;
            }
        }

        _cancelGridOrders(gridId, recipient, idList, flag);
    }

    /// @notice Cancel specific orders within a grid by ID list
    /// @param gridId The grid ID containing the orders
    /// @param recipient The address to receive the withdrawn tokens
    /// @param idList Array of order IDs to cancel
    /// @param flag Bit flags: 1 = base to ETH, 2 = quote to ETH
    function cancelGridOrders(uint128 gridId, address recipient, uint256[] memory idList, uint32 flag) external {
        _cancelGridOrders(gridId, recipient, idList, flag);
    }

    function _cancelGridOrders(uint128 gridId, address recipient, uint256[] memory idList, uint32 flag) internal {
        GridExStorage.Layout storage l = GridExStorage.layout();
        (uint64 pairId, uint256 baseAmt, uint256 quoteAmt) = l.gridState.cancelGridOrders(msg.sender, gridId, idList);

        IPair.Pair memory pair = l.getPairById[pairId];
        if (baseAmt > 0) {
            _transferAssetTo(pair.base, recipient, baseAmt, flag & 0x1);
        }
        if (quoteAmt > 0) {
            _transferAssetTo(pair.quote, recipient, quoteAmt, flag & 0x2);
        }
    }

    // ─── Withdraw & modify ───────────────────────────────────────────

    /// @notice Withdraw accumulated profits from a grid
    /// @param gridId The grid ID to withdraw profits from
    /// @param amt The amount to withdraw (0 = withdraw all)
    /// @param to The recipient address
    /// @param flag If quote is WETH and flag != 0, receive ETH instead
    function withdrawGridProfits(uint128 gridId, uint256 amt, address to, uint32 flag) external {
        GridExStorage.Layout storage l = GridExStorage.layout();
        IGridOrder.GridConfig memory conf = l.gridState.gridConfigs[gridId];
        if (conf.owner != msg.sender) {
            revert IOrderErrors.NotGridOwner();
        }

        if (amt == 0) {
            amt = conf.profits;
        } else if (conf.profits < amt) {
            amt = conf.profits;
        }

        if (amt == 0) {
            revert IOrderErrors.NoProfits();
        }

        if (amt >= 1 << 128) {
            revert IOrderErrors.ExceedMaxAmount();
        }

        IPair.Pair memory pair = l.getPairById[conf.pairId];

        // forge-lint: disable-next-line(unsafe-typecast)
        l.gridState.gridConfigs[gridId].profits = conf.profits - uint128(amt);

        // forge-lint: disable-next-line(unsafe-typecast)
        _transferAssetTo(pair.quote, to, uint128(amt), flag);

        emit WithdrawProfit(gridId, pair.quote, to, amt);
    }

    /// @notice Modify the fee for a grid
    /// @param gridId The grid ID to modify
    /// @param fee The new fee in basis points
    function modifyGridFee(uint128 gridId, uint32 fee) external {
        GridExStorage.Layout storage l = GridExStorage.layout();
        l.gridState.modifyGridFee(msg.sender, gridId, fee);
    }
}

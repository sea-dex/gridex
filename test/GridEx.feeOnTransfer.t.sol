// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {GridExBaseTest} from "./GridExBase.t.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IGridExRouter} from "../src/interfaces/IGridExRouter.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {ERC20} from "./utils/ERC20.sol";

contract GridExFeeOnTransferTest is GridExBaseTest {
    FeeOnTransferToken internal feeToken;

    function setUp() public override {
        super.setUp();
        feeToken = new FeeOnTransferToken("Fee Token", "FEE", 18, 100); // 1%
        feeToken.mint(maker, 1_000_000 ether);
        feeToken.mint(taker, 1_000_000 ether);

        vm.prank(maker);
        feeToken.approve(address(exchange), type(uint256).max);

        vm.prank(taker);
        feeToken.approve(address(exchange), type(uint256).max);
    }

    function test_placeGridOrders_revertWhenBaseIsFeeOnTransferToken() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int256(0)),
            bidData: "",
            askOrderCount: 1,
            bidOrderCount: 0,
            baseAmount: 1 ether,
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(TradeFacet.TransferInMismatch.selector);
        IGridExRouter(address(exchange))
            .placeGridOrders(Currency.wrap(address(feeToken)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    function test_fillBidOrder_revertWhenTakerPaysFeeOnTransferBase() public {
        uint256 bidPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: "",
            bidData: abi.encode(bidPrice0, int256(-1)),
            askOrderCount: 0,
            bidOrderCount: 1,
            baseAmount: 1 ether,
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.prank(maker);
        exchange.placeGridOrders(Currency.wrap(address(feeToken)), Currency.wrap(address(usdc)), param);

        vm.startPrank(taker);
        vm.expectRevert(TradeFacet.TransferInMismatch.selector);
        exchange.fillBidOrder(toGridOrderId(1, 0), 1 ether, 0, new bytes(0), 0);
        vm.stopPrank();
    }
}

contract FeeOnTransferToken is ERC20 {
    uint256 internal immutable FEE_BPS;
    uint256 internal constant BPS_DENOM = 10_000;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 feeBps_)
        ERC20(name_, symbol_, decimals_)
    {
        FEE_BPS = feeBps_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transferWithFee(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transferWithFee(from, to, amount);
        return true;
    }

    function _transferWithFee(address from, address to, uint256 amount) internal {
        uint256 fee = (amount * FEE_BPS) / BPS_DENOM;
        uint256 receiveAmount = amount - fee;

        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += receiveAmount;
        }
        emit Transfer(from, to, receiveAmount);

        if (fee > 0) {
            totalSupply -= fee;
            emit Transfer(from, address(0), fee);
        }
    }
}

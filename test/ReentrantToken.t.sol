// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {GridExBaseTest} from "test/GridExBase.t.sol";
import {IERC20Minimal} from "src/interfaces/IERC20Minimal.sol";
import {ERC20} from "test/utils/ERC20.sol";

contract ReentrantToken is ERC20 {
    address public exchange;
    uint64 public targetOrderId;
    uint128 public targetAmt;
    bool public reentered;
    bool public reentrySucceeded;

    constructor() ERC20("Reentrant Token", "RNT", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configureReentry(address _exchange, uint64 _orderId, uint128 _amt) external {
        exchange = _exchange;
        targetOrderId = _orderId;
        targetAmt = _amt;
        reentered = false;
        reentrySucceeded = false;
    }

    function approveToken(address token, address spender, uint256 amount) external {
        IERC20Minimal(token).approve(spender, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool ok = super.transfer(to, amount);
        if (msg.sender == exchange && !reentered) {
            reentered = true;
            (bool success,) = exchange.call(
                abi.encodeWithSignature(
                    "fillAskOrder(uint64,uint128,uint128,bytes,uint32)",
                    targetOrderId,
                    targetAmt,
                    uint128(0),
                    bytes(""),
                    uint32(0)
                )
            );
            reentrySucceeded = success;
        }
        return ok;
    }
}

contract FillReentrancyGuardBypassTest is GridExBaseTest {
    function test_cancelGrid_allowsReentrantFillDuringTransfer() public {
        ReentrantToken rnt = new ReentrantToken();
        rnt.mint(maker, 1000 ether);

        vm.startPrank(maker);
        rnt.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        // Grid 1: SEA/USDC (target fill for reentrancy)
        _placeOrders(address(sea), address(usdc), amt, 1, 1, askPrice0, bidPrice0, gap, false, 500);
        uint64 targetOrderId = toGridOrderId(1, 0x8000); // ask order

        // Grid 2: Reentrant token/USDC (cancel will trigger reentry in transfer)
        _placeOrdersBy(maker, address(rnt), address(usdc), amt, 1, 0, askPrice0, bidPrice0, gap, false, 500);

        // Fund the reentrant token with USDC so the inner fill can pay
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        usdc.transfer(address(rnt), 1_000_000_000);
        rnt.approveToken(address(usdc), address(exchange), type(uint256).max);
        rnt.configureReentry(address(exchange), targetOrderId, amt);

        uint256 seaBefore = sea.balanceOf(address(rnt));

        // Canceling grid 2 transfers RNT to maker; transfer() reenters fillAskOrder.
        vm.prank(maker);
        exchange.cancelGrid(maker, 2, 0);

        uint256 seaAfter = sea.balanceOf(address(rnt));

        // If the global guard were enforced, reentry would be blocked.
        assertFalse(rnt.reentrySucceeded(), "Reentrant fill should have been blocked by guard");
        assertEq(seaAfter - seaBefore, 0, "Reentrant fill should not receive SEA");
    }
}

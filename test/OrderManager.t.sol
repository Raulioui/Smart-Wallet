// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {OrderManager} from "../src/OrderManager.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockChainlinkFeed} from "./mocks/MockChainlinkFeed.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract OrderManagerTest is Test {
    OrderManager orderManager;
    MockERC20 usdc;
    MockERC20 weth;
    MockChainlinkFeed mockFeed;

    address wallet = makeAddr("smartWallet");

    uint256 constant AMOUNT = 100e6;        // 100 USDC
    uint256 constant MIN_OUT = 0.025e18;    // 0.025 WETH
    uint256 constant TARGET_PRICE = 3800e8; // $3800 (8 decimals, Chainlink format)
    uint256 constant INTERVAL = 7 days;  // DCA every 7 days
    uint256 constant EXECUTIONS = 4; // DCA executed 4 days

    // Default price below target
    int256 constant DEFAULT_FEED_PRICE = 3500e8;

    function setUp() public {
        orderManager = new OrderManager(address(this));
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        mockFeed = new MockChainlinkFeed(DEFAULT_FEED_PRICE, 8);
    }

    /////////////////////
    // Helpers
    /////////////////////

    function _createDCA() internal returns (uint256 orderId) {
        vm.prank(wallet);
        orderId = orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, INTERVAL, EXECUTIONS, 0);
    }

    function _createLimitBuy() internal returns (uint256 orderId) {
        vm.prank(wallet);
        orderId = orderManager.createLimitBuyOrder(
            address(usdc), address(weth), AMOUNT, MIN_OUT, TARGET_PRICE, address(mockFeed), 0
        );
    }

    function _createLimitSell() internal returns (uint256 orderId) {
        vm.prank(wallet);
        orderId = orderManager.createLimitSellOrder(
            address(weth), address(usdc), 1e18, 3800e6, TARGET_PRICE, address(mockFeed), 0
        );
    }

    function _createStopLoss() internal returns (uint256 orderId) {
        vm.prank(wallet);
        orderId = orderManager.createStopLossOrder(
            address(weth), address(usdc), 1e18, 2900e6, TARGET_PRICE, address(mockFeed), 0
        );
    }

    /////////////////////
    // DCA
    /////////////////////

    function test_CreateDCAOrder() public {
        uint256 orderId = _createDCA();

        OrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(order.wallet, wallet);
        assertEq(uint8(order.orderType), uint8(OrderManager.OrderType.DCA));
        assertEq(uint8(order.status), uint8(OrderManager.OrderStatus.ACTIVE));
        assertEq(order.tokenIn, address(usdc));
        assertEq(order.tokenOut, address(weth));
        assertEq(order.amountPerExecution, AMOUNT);
        assertEq(order.intervalSeconds, INTERVAL);
        assertEq(order.executionsLeft, EXECUTIONS);
        assertEq(order.nextExecutionTime, block.timestamp);
    }

    function test_CreateDCAOrder_InvalidParams() public {
        vm.startPrank(wallet);

        vm.expectRevert(OrderManager.OrderManager__InvalidParams.selector);
        orderManager.createDCAOrder(address(0), address(weth), AMOUNT, INTERVAL, EXECUTIONS, 0);

        vm.expectRevert(OrderManager.OrderManager__InvalidParams.selector);
        orderManager.createDCAOrder(address(usdc), address(weth), 0, INTERVAL, EXECUTIONS, 0);

        vm.expectRevert(OrderManager.OrderManager__InvalidParams.selector);
        orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, 0, EXECUTIONS, 0);

        vm.expectRevert(OrderManager.OrderManager__InvalidParams.selector);
        orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, 1 hours, EXECUTIONS, 0);

        vm.stopPrank();
    }

    function test_CreateDCAOrder_Infinite() public {
        // totalExecutions = 0 means infinite 
        vm.prank(wallet);
        uint256 orderId = orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, INTERVAL, 0, 0);

        assertEq(orderManager.getOrder(orderId).executionsLeft, type(uint256).max);
        assertEq(uint8(orderManager.getOrder(orderId).status), uint8(OrderManager.OrderStatus.ACTIVE));
    }

    function test_CreateDCAOrder_EmitsEvent() public {
        vm.prank(wallet);
        vm.expectEmit(true, true, false, true);
        emit OrderManager.OrderCreated(0, wallet, OrderManager.OrderType.DCA);
        orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, INTERVAL, EXECUTIONS, 0);
    }

    /////////////////////
    // Limit Orders - Buy/Sell/StopLoss
    /////////////////////

    function test_CreateLimitBuyOrder() public {
        uint256 orderId = _createLimitBuy();

        OrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint8(order.orderType), uint8(OrderManager.OrderType.LIMIT_BUY));
        assertEq(order.amountIn, AMOUNT);
        assertEq(order.minAmountOut, MIN_OUT);
        assertEq(order.targetPrice, TARGET_PRICE);
        assertEq(order.priceFeed, address(mockFeed));
        assertEq(order.executionsLeft, 1);
    }

    function test_CreateLimitSellOrder() public {
        uint256 orderId = _createLimitSell();

        OrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint8(order.orderType), uint8(OrderManager.OrderType.LIMIT_SELL));
        assertEq(uint8(order.status), uint8(OrderManager.OrderStatus.ACTIVE));
    }

    function test_CreateStopLossOrder() public {
        uint256 orderId = _createStopLoss();

        OrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint8(order.orderType), uint8(OrderManager.OrderType.STOP_LOSS));
        assertEq(uint8(order.status), uint8(OrderManager.OrderStatus.ACTIVE));
    }

    function test_CreatePriceBased_InvalidParams() public {
        vm.startPrank(wallet);

        vm.expectRevert(OrderManager.OrderManager__InvalidParams.selector);
        orderManager.createLimitBuyOrder(address(0), address(weth), AMOUNT, MIN_OUT, TARGET_PRICE, address(mockFeed), 0);

        vm.expectRevert(OrderManager.OrderManager__InvalidParams.selector);
        orderManager.createLimitBuyOrder(address(usdc), address(weth), 0, MIN_OUT, TARGET_PRICE, address(mockFeed), 0);

        vm.expectRevert(OrderManager.OrderManager__InvalidParams.selector);
        orderManager.createLimitBuyOrder(address(usdc), address(weth), AMOUNT, MIN_OUT, TARGET_PRICE, address(0), 0);

        vm.stopPrank();
    }

    function test_RecordExecution_DCA() public {
        uint256 orderId = _createDCA();

        vm.prank(wallet);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);

        OrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(order.executionsLeft, EXECUTIONS - 1);
        assertEq(order.nextExecutionTime, block.timestamp + INTERVAL);
        assertEq(uint8(order.status), uint8(OrderManager.OrderStatus.ACTIVE));
    }

    function test_RecordExecution_DCA_LastExecution() public {
        vm.prank(wallet);
        uint256 orderId = orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, INTERVAL, 1, 0);

        vm.prank(wallet);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);

        OrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(order.executionsLeft, 0);
        assertEq(uint8(order.status), uint8(OrderManager.OrderStatus.COMPLETED));
    }

    function test_RecordExecution_DCA_TooEarly() public {
        uint256 orderId = _createDCA();

        // Execute once (nextExecutionTime = now + INTERVAL)
        vm.prank(wallet);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);

        // Try to execute again before interval passes
        vm.prank(wallet);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrderManager.OrderManager__TooEarlyToExecute.selector,
                block.timestamp + INTERVAL
            )
        );
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);
    }

    function test_RecordExecution_DCA_AfterInterval() public {
        uint256 orderId = _createDCA();

        vm.prank(wallet);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);

        vm.warp(block.timestamp + INTERVAL);

        vm.prank(wallet);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);

        assertEq(orderManager.getOrder(orderId).executionsLeft, EXECUTIONS - 2);
    }

    function test_RecordExecution_NotOrderWallet() public {
        uint256 orderId = _createDCA();

        vm.prank(makeAddr("hacker"));
        vm.expectRevert(OrderManager.OrderManager__NotOrderWallet.selector);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);
    }

    function test_RecordExecution_NotActive() public {
        uint256 orderId = _createDCA();

        vm.prank(wallet);
        orderManager.cancelOrder(orderId);

        vm.prank(wallet);
        vm.expectRevert(OrderManager.OrderManager__OrderNotActive.selector);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);
    }

    function test_RecordExecution_LimitBuy_Completes() public {
        // Default feed: 3500e8 < TARGET_PRICE 3800e8 → price <= target, condition met
        uint256 orderId = _createLimitBuy();

        vm.prank(wallet);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);

        assertEq(uint8(orderManager.getOrder(orderId).status), uint8(OrderManager.OrderStatus.COMPLETED));
    }

    function test_RecordExecution_LimitSell_Completes() public {
        uint256 orderId = _createLimitSell();
        // Price must be >= TARGET_PRICE for LIMIT_SELL to execute
        mockFeed.setPrice(4000e8);

        vm.prank(wallet);
        orderManager.recordExecution(orderId, 1e18, 3800e6);

        assertEq(uint8(orderManager.getOrder(orderId).status), uint8(OrderManager.OrderStatus.COMPLETED));
    }

    function test_RecordExecution_StopLoss_Completes() public {
        // Default feed: 3500e8 < TARGET_PRICE 3800e8 → price <= target, condition met
        uint256 orderId = _createStopLoss();

        vm.prank(wallet);
        orderManager.recordExecution(orderId, 1e18, 2900e6);

        assertEq(uint8(orderManager.getOrder(orderId).status), uint8(OrderManager.OrderStatus.COMPLETED));
    }

    function test_RecordExecution_LimitBuy_PriceNotMet() public {
        uint256 orderId = _createLimitBuy();
        // Price above target → condition not met
        mockFeed.setPrice(4000e8);

        vm.prank(wallet);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrderManager.OrderManager__PriceConditionNotMet.selector,
                uint256(4000e8),
                TARGET_PRICE
            )
        );
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);
    }

    function test_RecordExecution_LimitSell_PriceNotMet() public {
        uint256 orderId = _createLimitSell();
        // Default feed 3500e8 < TARGET_PRICE → condition not met for LIMIT_SELL

        vm.prank(wallet);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrderManager.OrderManager__PriceConditionNotMet.selector,
                uint256(DEFAULT_FEED_PRICE),
                TARGET_PRICE
            )
        );
        orderManager.recordExecution(orderId, 1e18, 3800e6);
    }

    function test_RecordExecution_ExpiredOrder() public {
        uint256 validUntil = block.timestamp + 1 days;
        vm.prank(wallet);
        uint256 orderId =
            orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, INTERVAL, EXECUTIONS, validUntil);

        vm.warp(block.timestamp + 2 days);

        vm.prank(wallet);
        vm.expectRevert(OrderManager.OrderManager__OrderExpired.selector);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);
    }

    function test_ExpireOrder() public {
        uint256 validUntil = block.timestamp + 1 days;
        vm.prank(wallet);
        uint256 orderId =
            orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, INTERVAL, EXECUTIONS, validUntil);

        vm.warp(block.timestamp + 2 days);
        orderManager.expireOrder(orderId);

        assertEq(uint8(orderManager.getOrder(orderId).status), uint8(OrderManager.OrderStatus.EXPIRED));
    }

    function test_ExpireOrder_EmitsEvent() public {
        uint256 validUntil = block.timestamp + 1 days;
        vm.prank(wallet);
        uint256 orderId =
            orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, INTERVAL, EXECUTIONS, validUntil);

        vm.warp(block.timestamp + 2 days);

        vm.expectEmit(true, false, false, false);
        emit OrderManager.OrderExpired(orderId);
        orderManager.expireOrder(orderId);
    }

    function test_ExpireOrder_NotExpiredYet() public {
        uint256 validUntil = block.timestamp + 1 days;
        vm.prank(wallet);
        uint256 orderId =
            orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, INTERVAL, EXECUTIONS, validUntil);

        vm.expectRevert(OrderManager.OrderManager__OrderNotExpired.selector);
        orderManager.expireOrder(orderId);
    }

    function test_ExpireOrder_NoExpiry() public {
        uint256 orderId = _createDCA(); // validUntil = 0

        vm.expectRevert(OrderManager.OrderManager__OrderNotExpired.selector);
        orderManager.expireOrder(orderId);
    }

    /////////////////////
    // Fee Config
    /////////////////////

    function test_SetFeeConfig() public {
        address feeCollector = makeAddr("feeCollector");
        orderManager.setFeeConfig(feeCollector, 10); // 0.1%

        (address collector, uint256 bps) = orderManager.getFeeConfig();
        assertEq(collector, feeCollector);
        assertEq(bps, 10);
    }

    function test_SetFeeConfig_MaxExceeded() public {
        vm.expectRevert(OrderManager.OrderManager__InvalidParams.selector);
        orderManager.setFeeConfig(makeAddr("feeCollector"), 101); // > 1%
    }

    function test_SetFeeConfig_OnlyOwner() public {
        vm.prank(makeAddr("hacker"));
        vm.expectRevert();
        orderManager.setFeeConfig(makeAddr("feeCollector"), 10);
    }

    function test_FeeCharged_EmittedOnExecution() public {
        address feeCollector = makeAddr("feeCollector");
        orderManager.setFeeConfig(feeCollector, 100); // 1%

        uint256 orderId = _createDCA();
        uint256 expectedFee = (MIN_OUT * 100) / 10_000;

        vm.prank(wallet);
        vm.expectEmit(true, false, false, true);
        emit OrderManager.FeeCharged(orderId, feeCollector, expectedFee);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);
    }

    function test_NoFeeEmitted_WhenFeeNotConfigured() public {
        uint256 orderId = _createDCA();

        vm.prank(wallet);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);

        assertEq(orderManager.getOrder(orderId).executionsLeft, EXECUTIONS - 1);
    }

    function test_CancelOrder() public {
        uint256 orderId = _createDCA();

        vm.prank(wallet);
        orderManager.cancelOrder(orderId);

        assertEq(uint8(orderManager.getOrder(orderId).status), uint8(OrderManager.OrderStatus.CANCELLED));
    }

    function test_CancelOrder_NotWallet() public {
        uint256 orderId = _createDCA();

        vm.prank(makeAddr("hacker"));
        vm.expectRevert(OrderManager.OrderManager__NotOrderWallet.selector);
        orderManager.cancelOrder(orderId);
    }

    function test_CancelOrder_AlreadyCancelled() public {
        uint256 orderId = _createDCA();

        vm.startPrank(wallet);
        orderManager.cancelOrder(orderId);

        vm.expectRevert(OrderManager.OrderManager__OrderNotActive.selector);
        orderManager.cancelOrder(orderId);
        vm.stopPrank();
    }

    /////////////////////
    // Getters
    /////////////////////

    function test_GetActiveOrderIds() public {
        uint256 id0 = _createDCA();
        uint256 id1 = _createLimitBuy();
        uint256 id2 = _createStopLoss();

        vm.prank(wallet);
        orderManager.cancelOrder(id1);

        uint256[] memory active = orderManager.getActiveOrderIds();
        assertEq(active.length, 2);
        assertEq(active[0], id0);
        assertEq(active[1], id2);
    }

    function test_GetWalletOrders() public {
        _createDCA();
        _createLimitBuy();

        uint256[] memory orders = orderManager.getUserOrders(wallet);
        assertEq(orders.length, 2);
    }

    function test_GetTotalOrders() public {
        assertEq(orderManager.getTotalOrders(), 0);
        _createDCA();
        _createLimitBuy();
        assertEq(orderManager.getTotalOrders(), 2);
    }

    function test_GetActiveUserOrders() public {
        uint256 id0 = _createDCA();
        uint256 id1 = _createLimitBuy();
        _createStopLoss(); 

        vm.prank(wallet);
        orderManager.cancelOrder(id1);

        // Complete the stop loss (default feed price 3500e8 < TARGET_PRICE → condition met)
        vm.prank(wallet);
        orderManager.recordExecution(2, 1e18, 2900e6);

        uint256[] memory active = orderManager.getActiveUserOrders(wallet);
        assertEq(active.length, 1);
        assertEq(active[0], id0);
    }

    function test_RecordExecution_DCA_InfiniteNeverCompletes() public {
        vm.prank(wallet);
        uint256 orderId = orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, INTERVAL, 0, 0);

        // Execute 3 times across intervals
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(wallet);
            orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);
            vm.warp(block.timestamp + INTERVAL);
        }

        OrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint8(order.status), uint8(OrderManager.OrderStatus.ACTIVE));
        assertEq(order.executionsLeft, type(uint256).max - 3);
    }

    function test_CreateDCAOrder_ExactMinInterval() public {
        // Exactly 1 day should pass
        vm.prank(wallet);
        uint256 orderId = orderManager.createDCAOrder(address(usdc), address(weth), AMOUNT, 1 days, EXECUTIONS, 0);
        assertEq(orderManager.getOrder(orderId).intervalSeconds, 1 days);
    }

    function test_RecordExecution_StalePriceFeed() public {
        uint256 orderId = _createLimitBuy();

        // Warp forward so subtracting hours doesn't underflow (block.timestamp starts at 1 in Foundry)
        vm.warp(block.timestamp + 3 hours);
        // Feed was updated 2 hours ago, exceeds 1 hour staleness threshold
        mockFeed.setUpdatedAt(block.timestamp - 2 hours);

        vm.prank(wallet);
        vm.expectRevert(OrderManager.OrderManager__StalePriceFeed.selector);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);
    }

    function test_RecordExecution_FreshFeedPasses() public {
        uint256 orderId = _createLimitBuy();

        vm.warp(block.timestamp + 3 hours);
        // Feed updated 30 minutes ago 
        mockFeed.setUpdatedAt(block.timestamp - 30 minutes);

        vm.prank(wallet);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);

        assertEq(uint8(orderManager.getOrder(orderId).status), uint8(OrderManager.OrderStatus.COMPLETED));
    }

    /////////////////////
    // Pause / Unpause
    /////////////////////

    function test_Pause_BlocksExecution() public {
        uint256 orderId = _createDCA();
        orderManager.pause();

        vm.prank(wallet);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);
    }

    function test_Unpause_AllowsExecution() public {
        uint256 orderId = _createDCA();
        orderManager.pause();
        orderManager.unpause();

        vm.prank(wallet);
        orderManager.recordExecution(orderId, AMOUNT, MIN_OUT);

        assertEq(orderManager.getOrder(orderId).executionsLeft, EXECUTIONS - 1);
    }

    function test_Pause_OnlyOwner() public {
        vm.prank(makeAddr("hacker"));
        vm.expectRevert();
        orderManager.pause();
    }

    function test_Unpause_OnlyOwner() public {
        orderManager.pause();

        vm.prank(makeAddr("hacker"));
        vm.expectRevert();
        orderManager.unpause();
    }
}

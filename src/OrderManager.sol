// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title OrderManager
/// @notice Store the users orders and updates their status after execution.
/// Order types: DCA, LIMIT_BUY, LIMIT_SELL, STOP_LOSS.
/// @dev The actual execution of the swaps is done by the off-chain executor, that reads active orders every minute 
/// and checks if the conditions are met (time for DCA, price for LIMIT/STOP orders). If so,
/// it executes the swap and recordExecution is recorded inside the SmartWallet's executeBatch in entryPoint.
/// @author Raul
contract OrderManager is Ownable, Pausable {

    /////////////////////
    // Errors
    /////////////////////
    error OrderManager__NotOrderWallet();
    error OrderManager__OrderNotActive();
    error OrderManager__InvalidParams();
    error OrderManager__TooEarlyToExecute(uint256 nextExecutionTime);
    error OrderManager__OrderExpired();
    error OrderManager__OrderNotExpired();
    error OrderManager__PriceConditionNotMet(uint256 currentPrice, uint256 targetPrice);
    error OrderManager__StalePriceFeed();

    /////////////////////
    // Types
    /////////////////////
    enum OrderType {
        DCA,
        LIMIT_BUY,   // buy when price <= targetPrice
        LIMIT_SELL,  // sell when price >= targetPrice (take profit)
        STOP_LOSS    // sell when price <= targetPrice (protect downside)
    }

    enum OrderStatus {
        ACTIVE,
        COMPLETED,
        CANCELLED,
        EXPIRED
    }

    struct Order {
        uint256 id;
        address wallet;
        OrderType orderType;
        OrderStatus status;
        address tokenIn;
        address tokenOut;
        // DCA
        uint256 amountPerExecution;
        uint256 intervalSeconds;
        uint256 nextExecutionTime;
        uint256 executionsLeft;
        // LIMIT_BUY, LIMIT_SELL, STOP_LOSS
        uint256 amountIn;
        uint256 minAmountOut;     // slippage protection
        uint256 targetPrice;      // Chainlink price trigger (8 decimals)
        address priceFeed;        // Chainlink feed address
        // Common
        uint256 validUntil;       // 0 = no expiry
        uint256 createdAt;
    }

    /////////////////////
    // Storage
    /////////////////////

    mapping(uint256 => Order) private orders;
    mapping(address => uint256[]) private userOrders;
    uint256 private nextOrderId;

    address public feeCollector;
    uint256 public feeBps; // basis points — 10 = 0.1%

    /// @notice Minimum interval for DCA orders to prevent spam and overloading the executor.
    uint256 private constant MIN_DCA_INTERVAL = 1 days;

    /////////////////////
    // Events
    /////////////////////
    event OrderCreated(uint256 indexed orderId, address indexed wallet, OrderType orderType);
    event OrderExecuted(uint256 indexed orderId, uint256 amountIn, uint256 amountOut, uint256 executionsLeft);
    event OrderCancelled(uint256 indexed orderId);
    event OrderCompleted(uint256 indexed orderId);
    event OrderExpired(uint256 indexed orderId);
    /// @dev Off-chain executor reads this event to know how much fee to include in executeBatch.
    event FeeCharged(uint256 indexed orderId, address feeCollector, uint256 feeAmount);

    /////////////////////
    // Constructor
    /////////////////////
    constructor(address initialOwner) Ownable(initialOwner) {}

    /////////////////////
    // External Functions
    /////////////////////

    /// @notice Invest a fixed amount at regular intervals (e.g. 100 USDC → ETH every week for 12 weeks).
    /// @dev If totalExecutions is 0 DCA is indefinite until cancelled. Otherwise,
    ///  it automatically completes after the specified number of executions.
    function createDCAOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountPerExecution,
        uint256 intervalSeconds,
        uint256 totalExecutions,
        uint256 validUntil
    ) external returns (uint256 orderId) {
        if (tokenIn == address(0) || tokenOut == address(0)) revert OrderManager__InvalidParams();
        if (amountPerExecution == 0 || intervalSeconds == 0) revert OrderManager__InvalidParams();
        if (intervalSeconds < MIN_DCA_INTERVAL) revert OrderManager__InvalidParams();

        orderId = nextOrderId++;
        orders[orderId] = Order({
            id: orderId,
            wallet: msg.sender,
            orderType: OrderType.DCA,
            status: OrderStatus.ACTIVE,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountPerExecution: amountPerExecution,
            intervalSeconds: intervalSeconds,
            nextExecutionTime: block.timestamp,
            executionsLeft: totalExecutions == 0 ? type(uint256).max : totalExecutions, // if totalExecutions is 0 → infinite DCA until cancelled
            amountIn: 0,
            minAmountOut: 0,
            targetPrice: 0,
            priceFeed: address(0),
            validUntil: validUntil,
            createdAt: block.timestamp
        });

        userOrders[msg.sender].push(orderId);

        emit OrderCreated(orderId, msg.sender, OrderType.DCA);
    }

    /// @notice Buy tokenOut when its price drops to or below targetPrice.
    function createLimitBuyOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 targetPrice,
        address priceFeed,
        uint256 validUntil
    ) external returns (uint256 orderId) {
        orderId = _createPriceBased(OrderType.LIMIT_BUY, tokenIn, tokenOut, amountIn, minAmountOut, targetPrice, priceFeed, validUntil);
    }

    /// @notice Sell tokenIn when its price rises to or above targetPrice (take profit).
    function createLimitSellOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 targetPrice,
        address priceFeed,
        uint256 validUntil
    ) external returns (uint256 orderId) {
        orderId = _createPriceBased(OrderType.LIMIT_SELL, tokenIn, tokenOut, amountIn, minAmountOut, targetPrice, priceFeed, validUntil);
    }

    /// @notice Sell tokenIn when its price drops to or below targetPrice (stop loss).
    function createStopLossOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 targetPrice,
        address priceFeed,
        uint256 validUntil
    ) external returns (uint256 orderId) {
        orderId = _createPriceBased(OrderType.STOP_LOSS, tokenIn, tokenOut, amountIn, minAmountOut, targetPrice, priceFeed, validUntil);
    }

    /// @notice Called by the SmartWallet as the last call inside executeBatch in entryPoint.
    /// @dev If expiry or price condition fails → reverts → the whole batch reverts including the swap.
    /// @dev Is used for update the state after the swap is executed.
    function recordExecution(uint256 orderId, uint256 amountIn, uint256 amountOut) external whenNotPaused {
        Order storage order = orders[orderId];
        if (order.wallet != msg.sender) revert OrderManager__NotOrderWallet();
        if (order.status != OrderStatus.ACTIVE) revert OrderManager__OrderNotActive();

        // Expiry check
        if (order.validUntil != 0 && block.timestamp > order.validUntil) {
            revert OrderManager__OrderExpired();
        }

        if (order.orderType == OrderType.DCA) {
            if (block.timestamp < order.nextExecutionTime) {
                revert OrderManager__TooEarlyToExecute(order.nextExecutionTime);
            }
            order.nextExecutionTime = block.timestamp + order.intervalSeconds;
            order.executionsLeft -= 1;

            _emitFee(orderId, amountOut);
            emit OrderExecuted(orderId, amountIn, amountOut, order.executionsLeft);

            if (order.executionsLeft == 0) {
                order.status = OrderStatus.COMPLETED;
                emit OrderCompleted(orderId);
            }
        } else {
            // LIMIT_BUY, LIMIT_SELL, STOP_LOSS 
            _checkPriceCondition(order);

            order.status = OrderStatus.COMPLETED;
            _emitFee(orderId, amountOut);
            emit OrderExecuted(orderId, amountIn, amountOut, 0);
            emit OrderCompleted(orderId);
        }
    }

    /// @notice Marks an expired order as EXPIRED. Anyone can call this to clean up stale orders.
    function expireOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        if (order.status != OrderStatus.ACTIVE) revert OrderManager__OrderNotActive();
        if (order.validUntil == 0 || block.timestamp <= order.validUntil) revert OrderManager__OrderNotExpired();
        order.status = OrderStatus.EXPIRED;
        emit OrderExpired(orderId);
    }

    function cancelOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        if (order.wallet != msg.sender) revert OrderManager__NotOrderWallet();
        if (order.status != OrderStatus.ACTIVE) revert OrderManager__OrderNotActive();
        order.status = OrderStatus.CANCELLED;
        emit OrderCancelled(orderId);
    }

    /////////////////////
    // Owner Functions
    /////////////////////

    function setFeeConfig(address collector, uint256 bps) external onlyOwner {
        if (bps > 100) revert OrderManager__InvalidParams(); // max 1%
        feeCollector = collector;
        feeBps = bps;
    }

    function pause() external onlyOwner { _pause(); }

    function unpause() external onlyOwner { _unpause(); }

    /////////////////////
    // Internal Functions
    /////////////////////

    function _createPriceBased(
        OrderType orderType,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 targetPrice,
        address priceFeed,
        uint256 validUntil
    ) internal returns (uint256 orderId) {
        if (tokenIn == address(0) || tokenOut == address(0)) revert OrderManager__InvalidParams();
        if (amountIn == 0 || minAmountOut == 0 || targetPrice == 0 || priceFeed == address(0)) revert OrderManager__InvalidParams();

        orderId = nextOrderId++;
        orders[orderId] = Order({
            id: orderId,
            wallet: msg.sender,
            orderType: orderType,
            status: OrderStatus.ACTIVE,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountPerExecution: 0,
            intervalSeconds: 0,
            nextExecutionTime: 0,
            executionsLeft: 1,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            targetPrice: targetPrice,
            priceFeed: priceFeed,
            validUntil: validUntil,
            createdAt: block.timestamp
        });
        userOrders[msg.sender].push(orderId);
        emit OrderCreated(orderId, msg.sender, orderType);
    }

    /// @notice Reads Chainlink and verifies the price condition was met at execution time.
    /// @dev This makes the system trustless, in case a buggy executor executes at wrong prices.
    function _checkPriceCondition(Order storage order) internal view {
        (, int256 price,, uint256 updatedAt,) = AggregatorV3Interface(order.priceFeed).latestRoundData();
        if (block.timestamp - updatedAt > 1 hours) revert OrderManager__StalePriceFeed();
        uint256 currentPrice = uint256(price);

        if (order.orderType == OrderType.LIMIT_BUY || order.orderType == OrderType.STOP_LOSS) {
            // Execute only when price has dropped to or below target
            if (currentPrice > order.targetPrice) {
                revert OrderManager__PriceConditionNotMet(currentPrice, order.targetPrice);
            }
        } else {
            // LIMIT_SELL: execute only when price has risen to or above target
            if (currentPrice < order.targetPrice) {
                revert OrderManager__PriceConditionNotMet(currentPrice, order.targetPrice);
            }
        }
    }

    /// @notice Emits the fee amount so the executor knows how much to transfer in the batch.
    /// @dev Actual token transfer is included by the executor in executeBatch.
    function _emitFee(uint256 orderId, uint256 amountOut) internal {
        if (feeBps > 0 && feeCollector != address(0)) {
            uint256 fee = (amountOut * feeBps) / 10_000;
            emit FeeCharged(orderId, feeCollector, fee);
        }
    }

    /////////////////////
    // Getter Functions
    /////////////////////

    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    function getUserOrders(address wallet) external view returns (uint256[] memory) {
        return userOrders[wallet];
    }

    function getActiveOrderIds() external view returns (uint256[] memory) {
        uint256 total = nextOrderId;
        uint256 count = 0;
        for (uint256 i = 0; i < total; i++) {
            if (orders[i].status == OrderStatus.ACTIVE) count++;
        }
        uint256[] memory activeIds = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < total; i++) {
            if (orders[i].status == OrderStatus.ACTIVE) activeIds[idx++] = i;
        }
        return activeIds;
    }

    function getTotalOrders() external view returns (uint256) {
        return nextOrderId;
    }

    function getFeeConfig() external view returns (address, uint256) {
        return (feeCollector, feeBps);
    }

    function getActiveUserOrders(address user) external view returns (uint256[] memory) {
        uint256[] memory allOrders = userOrders[user];
        uint256 count = 0;
        for (uint256 i = 0; i < allOrders.length; i++) {
            if (orders[allOrders[i]].status == OrderStatus.ACTIVE) count++;
        }
        uint256[] memory activeOrders = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < allOrders.length; i++) {
            if (orders[allOrders[i]].status == OrderStatus.ACTIVE) {
                activeOrders[idx++] = allOrders[i];
            }
        }
        return activeOrders;
    }
}

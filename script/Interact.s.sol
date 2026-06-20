// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SmartWalletFactory} from "../src/SmartWalletFactory.sol";
import {SmartWallet} from "../src/SmartWallet.sol";
import {OrderManager} from "../src/OrderManager.sol";

contract InteractScript is Script {
    address constant FACTORY       = 0xE097784c26fCf1b3A5D737DF5ef48dcBae325939;
    address constant ORDER_MANAGER = 0x1e29B2021541Fafd759C781508868FD5dc97a3f6;

    address constant TOKEN_IN  = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC Base Sepolia
    address constant TOKEN_OUT = 0x4200000000000000000000000000000000000006; // WETH Base Sepolia

    // Fake Chainlink feed address
    address constant PRICE_FEED = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1; // ETH/USD Base Sepolia

    function run() external {
        require(FACTORY != address(0) && ORDER_MANAGER != address(0), "Fill deployed addresses first");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        SmartWalletFactory factory = SmartWalletFactory(FACTORY);
        OrderManager orderManager = OrderManager(ORDER_MANAGER);

        vm.startBroadcast(deployerKey);

        // Create (or retrieve) SmartWallet
        address predicted = factory.getAddress(deployer, 0);
        console.log("Predicted wallet address:", predicted);

        SmartWallet wallet = factory.createWallet(deployer, 0);
        console.log("SmartWallet deployed at: ", address(wallet));
        console.log("Owner:                   ", wallet.owner());

        // Create a DCA order 
        bytes memory createOrderCall = abi.encodeWithSelector(
            OrderManager.createDCAOrder.selector,
            TOKEN_IN,
            TOKEN_OUT,
            100e6,    // 100 USDC per execution
            7 days,   // every 7 days
            4,        // 4 executions
            0         // no expiry
        );
        wallet.execute(ORDER_MANAGER, 0, createOrderCall);
        console.log("DCA order created. Order ID: 0");

        // Read order back and verify
        OrderManager.Order memory order = orderManager.getOrder(0);
        require(order.wallet == address(wallet), "Order wallet mismatch");
        require(order.tokenIn == TOKEN_IN,        "Token mismatch");
        require(uint8(order.status) == uint8(OrderManager.OrderStatus.ACTIVE), "Order not ACTIVE");

        // Create a limit buy order 
        bytes memory limitBuyCall = abi.encodeWithSelector(
            OrderManager.createLimitBuyOrder.selector,
            TOKEN_IN,
            TOKEN_OUT,
            100e6,     
            0.025e18,    
            3500e8,      // targetPrice $3500 (8 decimals)
            PRICE_FEED,
            0            // no expiry
        );
        wallet.execute(ORDER_MANAGER, 0, limitBuyCall);

        // Cancel the limit buy to test cancel flow
        bytes memory cancelCall = abi.encodeWithSelector(
            OrderManager.cancelOrder.selector,
            uint256(1)
        );
        wallet.execute(ORDER_MANAGER, 0, cancelCall);
        require(
            uint8(orderManager.getOrder(1).status) == uint8(OrderManager.OrderStatus.CANCELLED),
            "Order not CANCELLED"
        );

        // Test fee config 
        orderManager.setFeeConfig(deployer, 10); // 0.1%
        (address collector, uint256 bps) = orderManager.getFeeConfig();
        require(collector == deployer && bps == 10, "Fee config mismatch");

        // Verify getActiveOrderIds
        uint256[] memory activeIds = orderManager.getActiveOrderIds();
        require(activeIds.length == 1 && activeIds[0] == 0, "Active orders mismatch");
        vm.stopBroadcast();
    }
}

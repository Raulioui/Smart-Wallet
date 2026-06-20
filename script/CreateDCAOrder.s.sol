// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SmartWallet} from "../src/SmartWallet.sol";
import {OrderManager} from "../src/OrderManager.sol";

contract CreateDCAOrderScript is Script {
    address constant WALLET        = 0xd63Ea46Ec889e6fA89072E0083D88908F2918361;
    address constant ORDER_MANAGER = 0x1e29B2021541Fafd759C781508868FD5dc97a3f6;
    address constant USDC          = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant WETH          = 0x4200000000000000000000000000000000000006;

    function run() external {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(ownerKey);

        bytes memory callData = abi.encodeWithSelector(
            OrderManager.createDCAOrder.selector,
            USDC,
            WETH,
            10e6,    // 10 USD for execution
            1 days,  // every 1 day
            2,       // 2 executions
            0        // no expiration
        );

        SmartWallet(payable(WALLET)).execute(ORDER_MANAGER, 0, callData);

        uint256 orderId = OrderManager(ORDER_MANAGER).getTotalOrders() - 1;
        OrderManager.Order memory order = OrderManager(ORDER_MANAGER).getOrder(orderId);

        console.log("DCA order created:");
        console.log("  id:                ", order.id);
        console.log("  amountPerExecution:", order.amountPerExecution);
        console.log("  executionsLeft:    ", order.executionsLeft);
        console.log("  nextExecutionTime: ", order.nextExecutionTime);

        vm.stopBroadcast();
    }
}

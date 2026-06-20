// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SmartWalletFactory} from "../src/SmartWalletFactory.sol";
import {OrderManager} from "../src/OrderManager.sol";

contract DeployScript is Script {
    // EIP-4337 EntryPoint 
    address constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:   ", deployer);
        console.log("Chain ID:   ", block.chainid);
        console.log("EntryPoint: ", ENTRY_POINT);
        console.log("---");

        vm.startBroadcast(deployerKey);

        SmartWalletFactory factory = new SmartWalletFactory(ENTRY_POINT);
        console.log("SmartWalletFactory:", address(factory));

        OrderManager orderManager = new OrderManager(deployer);
        console.log("OrderManager:      ", address(orderManager));

        vm.stopBroadcast();

        console.log("---");
        console.log("Add to .env:");
        console.log("FACTORY_ADDRESS=", address(factory));
        console.log("ORDER_MANAGER_ADDRESS=", address(orderManager));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SmartWallet} from "../src/SmartWallet.sol";

contract AddSessionKeyScript is Script {
    address constant WALLET       = 0xd63Ea46Ec889e6fA89072E0083D88908F2918361;
    address constant EXECUTOR_KEY = 0xD5B95747CcCEa0E0115623e05d8067a666cfF9c8;

    function run() external {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(ownerKey);

        SmartWallet(payable(WALLET)).addSessionKey(
            EXECUTOR_KEY,
            SmartWallet.SessionKeyData({
                isActive: true,
                validUntil: uint48(block.timestamp + 365 days),
                maxAmountPerTx: 1000e6,  // 1,000 USDC per ejecución
                dailyLimit: 5000e6       // 5,000 USDC por día
            })
        );

        console.log("Session key added:");
        console.log("  wallet:   ", WALLET);
        console.log("  executor: ", EXECUTOR_KEY);

        vm.stopBroadcast();
    }
}

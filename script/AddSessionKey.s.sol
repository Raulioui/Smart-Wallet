// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SmartWallet} from "../src/SmartWallet.sol";

contract AddSessionKeyScript is Script {
    address constant WALLET        = 0xd63Ea46Ec889e6fA89072E0083D88908F2918361;
    address constant EXECUTOR_KEY  = 0xD5B95747CcCEa0E0115623e05d8067a666cfF9c8;
    address constant USDC          = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant SWAP_ROUTER   = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;
    address constant ORDER_MANAGER = 0x1e29B2021541Fafd759C781508868FD5dc97a3f6;

    function run() external {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");

        // Scope: executor may only call these contracts...
        address[] memory allowedDests = new address[](3);
        allowedDests[0] = USDC;
        allowedDests[1] = SWAP_ROUTER;
        allowedDests[2] = ORDER_MANAGER;

        // ...and only these function selectors.
        bytes4[] memory allowedSelectors = new bytes4[](3);
        allowedSelectors[0] = bytes4(0x095ea7b3); // approve(address,uint256)
        allowedSelectors[1] = bytes4(0x04e45aaf); // exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))
        allowedSelectors[2] = bytes4(0x0188e6a2); // recordExecution(uint256,uint256,uint256)

        vm.startBroadcast(ownerKey);

        SmartWallet(payable(WALLET)).addSessionKey(
            EXECUTOR_KEY,
            SmartWallet.SessionKeyData({
                isActive: true,
                validUntil: uint48(block.timestamp + 365 days),
                maxAmountPerTx: 1000e6,
                dailyLimit: 5000e6
            }),
            allowedDests,
            allowedSelectors
        );

        console.log("Session key added:");
        console.log("  wallet:   ", WALLET);
        console.log("  executor: ", EXECUTOR_KEY);

        vm.stopBroadcast();
    }
}

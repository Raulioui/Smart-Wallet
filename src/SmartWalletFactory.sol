// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SmartWallet} from "./SmartWallet.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

/// @title  SmartWalletFactory
/// @notice A factory contract for deploying SmartWallet instances using CREATE2.
/// @author Raul
contract SmartWalletFactory {

    error SmartWalletFactory__InvalidOwner();

    IEntryPoint private immutable i_entryPoint;

    event WalletCreated(address indexed wallet, address indexed owner);

    /////////////////////
    // Constructor
    /////////////////////
    constructor(address entryPoint) {
        i_entryPoint = IEntryPoint(entryPoint);
    }

    /////////////////////
    // External Functions
    /////////////////////

    /// @notice Deploys a SmartWallet for the given owner using CREATE2.
    /// @dev If the wallet is already deployed, returns the existing address.
    /// Salt allows one owner to have multiple wallets (salt=0 for the default one).
    function createWallet(address owner, uint256 salt) external returns (SmartWallet wallet) {
        if (owner == address(0)) revert SmartWalletFactory__InvalidOwner();

        address predicted = getAddress(owner, salt);

        // Already deployed,return it without deploying again
        if (predicted.code.length > 0) {
            return SmartWallet(payable(predicted));
        }

        wallet = new SmartWallet{salt: bytes32(salt)}(address(i_entryPoint), owner);
        emit WalletCreated(address(wallet), owner);
    }

    /////////////////////
    // Getters
    /////////////////////

    function getAddress(address owner, uint256 salt) public view returns (address) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(SmartWallet).creationCode,
                abi.encode(address(i_entryPoint), owner)
            )
        );
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), initCodeHash)
        ))));
    }

    function getEntryPoint() external view returns (address) {
        return address(i_entryPoint);
    }
}

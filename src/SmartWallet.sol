// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {
    SIG_VALIDATION_FAILED,
    SIG_VALIDATION_SUCCESS,
    _packValidationData
} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SmartWallet
/// @notice A simple, secure, and gas-efficient smart contract wallet with built-in support for EIP-4337 account abstraction.
/// Implements session keys allowing users to automate the orders.
/// @author Raul
contract SmartWallet is IAccount, Ownable, ReentrancyGuard {

    /////////////////////
    // Errors
    /////////////////////
    error SmartWallet__NotFromEntryPoint();
    error SmartWallet__NotFromEntryPointOrOwner();
    error SmartWallet__CallFailed(bytes result);
    error SmartWallet__InvalidSessionKey();
    error SmartWallet__ArrayLengthMismatch();

    /////////////////////
    // Storage
    /////////////////////
    /// @notice EIP-1271: returned by isValidSignature when the signature is valid.
    bytes4 private constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice Permissions granted to the off-chain executor.
    // Amount limits are enforced off-chain, the executor
    // reads them before building each UserOperation.
    struct SessionKeyData {
        bool isActive;
        uint48 validUntil;      // unix timestamp 
        uint256 maxAmountPerTx; // max tokens movable per single execution
        uint256 dailyLimit;     // max tokens movable per day
    }

    IEntryPoint private immutable i_entryPoint;
    mapping(address => SessionKeyData) private sessionKeys;

    /////////////////////
    // Events
    /////////////////////
    event SessionKeyAdded(address indexed key, uint48 validUntil);
    event SessionKeyRevoked(address indexed key);

    /////////////////////
    // Modifiers
    /////////////////////
    modifier requireFromEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert SmartWallet__NotFromEntryPoint();
        }
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != address(i_entryPoint) && msg.sender != owner()) {
            revert SmartWallet__NotFromEntryPointOrOwner();
        }
        _;
    }

    /////////////////////
    // Constructor
    /////////////////////
    constructor(address entryPoint, address initialOwner) Ownable(initialOwner) {
        i_entryPoint = IEntryPoint(entryPoint);
    }

    receive() external payable {}

    /////////////////////
    // External Functions
    /////////////////////

    /// @notice Single call used by owner from the frontend for simple operations.
    function execute(address dest, uint256 value, bytes calldata functionData)
        external
        requireFromEntryPointOrOwner
        nonReentrant
    {
        (bool success, bytes memory result) = dest.call{value: value}(functionData);
        if (!success) revert SmartWallet__CallFailed(result);
    }

    /// @notice Called by the executor to run approve + swap + recordExecution atomically.
    function executeBatch(
        address[] calldata dests,
        uint256[] calldata values,
        bytes[] calldata functionDatas
    ) external requireFromEntryPointOrOwner nonReentrant {
        if (dests.length != functionDatas.length) revert SmartWallet__ArrayLengthMismatch();
        if (values.length != 0 && values.length != dests.length) revert SmartWallet__ArrayLengthMismatch();

        for (uint256 i = 0; i < dests.length; i++) {
            uint256 value = values.length == 0 ? 0 : values[i];
            (bool success, bytes memory result) = dests[i].call{value: value}(functionDatas[i]);
            if (!success) revert SmartWallet__CallFailed(result);
        }
    }

    /// @notice EIP-4337: called by EntryPoint to validate the UserOperation.
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external requireFromEntryPoint returns (uint256 validationData) {
        validationData = _validateSignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    /// @notice EIP-1271: lets third-party protocols  verify that this
    /// wallet authorized a message signed off-chain, without a direct on-chain call.
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        address signer = ECDSA.recover(hash, signature);
        if (signer == owner()) return EIP1271_MAGIC_VALUE;
        SessionKeyData storage sk = sessionKeys[signer];
        if (sk.isActive && block.timestamp <= sk.validUntil) return EIP1271_MAGIC_VALUE;
        return bytes4(0xffffffff);
    }

    /////////////////////
    // Internal Functions
    /////////////////////

    /// @notice Validates the signature of a UserOperation.
    /// @dev Returns the validation data for the EntryPoint.
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);

        if (signer == owner()) return SIG_VALIDATION_SUCCESS;

        SessionKeyData storage sk = sessionKeys[signer];
        if (!sk.isActive) return SIG_VALIDATION_FAILED;

        return _packValidationData(false, sk.validUntil, 0);
    }

    /// @notice Sends ETH to EntryPoint if needed. No-op when a Paymaster covers the gas.
    /// @dev This is a workaround for the fact that EntryPoint doesn't support sending ETH to the wallet in the same transaction.
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            (success);
        }
    }

    /////////////////////
    // Session Key Management
    /////////////////////

    function addSessionKey(address key, SessionKeyData calldata params) external onlyOwner {
        if (key == address(0) || key == owner()) revert SmartWallet__InvalidSessionKey();
        sessionKeys[key] = params;
        sessionKeys[key].isActive = true;
        emit SessionKeyAdded(key, params.validUntil);
    }

    function revokeSessionKey(address key) external onlyOwner {
        sessionKeys[key].isActive = false;
        emit SessionKeyRevoked(key);
    }

    /////////////////////
    // Getter Functions
    /////////////////////

    function getEntryPoint() external view returns (address) {
        return address(i_entryPoint);
    }

    function getSessionKey(address key) external view returns (SessionKeyData memory) {
        return sessionKeys[key];
    }
}

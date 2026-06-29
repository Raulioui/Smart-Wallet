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
/// @notice EIP-4337 account with scoped session keys for DeFi order automation.
/// Session keys are restricted to a whitelist of (dest, selector) pairs and
/// spending limits enforced across validation and execution phases.
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
    error SmartWallet__DailyLimitExceeded();

    /////////////////////
    // Storage
    /////////////////////
    bytes4 private constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 private constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));

    struct SessionKeyData {
        bool isActive;
        uint48 validUntil;
        uint256 maxAmountPerTx; // enforced in validation phase (no TIMESTAMP - ERC-7562 compliant)
        uint256 dailyLimit;     // enforced in execution phase (TIMESTAMP allowed there)
    }

    IEntryPoint private immutable i_entryPoint;
    mapping(address => SessionKeyData) private sessionKeys;

    // Tracks daily spend per session key: signer => (timestamp / 1 days) => amount.
    // Written in executeBatch (execution phase) where TIMESTAMP is not restricted.
    mapping(address => mapping(uint256 => uint256)) private skDailySpent;

    // FIFO queue that pairs each validateUserOp call with its matching execute/executeBatch.
    // Necessary because the EntryPoint validates ALL ops in a bundle before executing ANY of them
    // (two separate loops). A single slot would be overwritten if the same wallet has two ops in
    // the same bundle. _validateSignature always pushes (address(0) for owner, signer for session
    // key). execute and executeBatch always pop when called by the EntryPoint.
    mapping(uint256 => address) private _skQueue;
    uint256 private _skHead; // next slot to consume (in execution)
    uint256 private _skTail; // next slot to write (in validation)

    // Generation counter per session key. Bumped on every addSessionKey call so
    // old scope entries are invalidated without needing to delete mappings.
    mapping(address => uint256) private skGeneration;

    // Scope whitelist: signer => generation => dest => allowed.
    // Also used as the approve() spender whitelist: a session key may only approve
    // contracts that are themselves whitelisted as destinations.
    mapping(address => mapping(uint256 => mapping(address => bool))) private skAllowedDests;

    // Scope whitelist: signer => generation => selector => allowed
    mapping(address => mapping(uint256 => mapping(bytes4 => bool))) private skAllowedSelectors;

    /////////////////////
    // Events
    /////////////////////
    event SessionKeyAdded(address indexed key, uint48 validUntil);
    event SessionKeyRevoked(address indexed key);

    /////////////////////
    // Modifiers
    /////////////////////
    modifier requireFromEntryPoint() {
        if (msg.sender != address(i_entryPoint)) revert SmartWallet__NotFromEntryPoint();
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

    /// @notice Single call used by the owner from the frontend.
    function execute(address dest, uint256 value, bytes calldata functionData)
        external
        requireFromEntryPointOrOwner
        nonReentrant
    {
        // Pop the queue entry pushed during validateUserOp. Always address(0) for owner.
        if (msg.sender == address(i_entryPoint)) {
            delete _skQueue[_skHead++];
        }
        (bool success, bytes memory result) = dest.call{value: value}(functionData);
        if (!success) revert SmartWallet__CallFailed(result);
    }

    /// @notice Atomic batch used by the executor: approve -> swap -> recordExecution.
    /// Daily limit is enforced here (execution phase) where TIMESTAMP is allowed.
    function executeBatch(
        address[] calldata dests,
        uint256[] calldata values,
        bytes[] calldata functionDatas
    ) external requireFromEntryPointOrOwner nonReentrant {
        if (dests.length != functionDatas.length) revert SmartWallet__ArrayLengthMismatch();
        if (values.length != 0 && values.length != dests.length) revert SmartWallet__ArrayLengthMismatch();

        if (msg.sender == address(i_entryPoint)) {
            // Pop the FIFO queue entry written during validateUserOp for this op.
            address signer = _skQueue[_skHead];
            delete _skQueue[_skHead++];

            if (signer != address(0)) {
                uint256 total = _sumApprovals(functionDatas);
                uint256 day = block.timestamp / 1 days;
                uint256 newTotal = skDailySpent[signer][day] + total;
                if (newTotal > sessionKeys[signer].dailyLimit) revert SmartWallet__DailyLimitExceeded();
                skDailySpent[signer][day] = newTotal;
            }
        }

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

    /// @notice EIP-1271: only the owner can sign arbitrary off-chain messages.
    /// Session keys are intentionally excluded - they cannot authorize Permit,
    /// Permit2 or any other off-chain flow that could drain the wallet without
    /// going through the executeBatch scope and limit checks.
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        address signer = ECDSA.recover(hash, signature);
        if (signer == owner()) return EIP1271_MAGIC_VALUE;
        return bytes4(0xffffffff);
    }

    /////////////////////
    // Internal Functions
    /////////////////////

    /// @notice Validates signature, scope and per-tx limit. Always pushes to _skQueue so
    /// execute/executeBatch can pop the matching entry regardless of who signed.
    /// ERC-7562 compliant: no TIMESTAMP or other banned opcodes used here.
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);

        if (signer == owner()) {
            // Push address(0) so execute/executeBatch pop a matching entry.
            _skQueue[_skTail++] = address(0);
            return SIG_VALIDATION_SUCCESS;
        }

        SessionKeyData storage sk = sessionKeys[signer];
        if (!sk.isActive) return SIG_VALIDATION_FAILED;

        // Session keys may only call executeBatch, never execute.
        if (userOp.callData.length < 4) return SIG_VALIDATION_FAILED;
        if (bytes4(userOp.callData[:4]) != this.executeBatch.selector) return SIG_VALIDATION_FAILED;

        // Validate every (dest, selector, spender) in the batch and sum approve amounts.
        uint256 gen = skGeneration[signer];
        (bool ok, uint256 amount) = _validateBatchScope(userOp.callData, signer, gen);
        if (!ok) return SIG_VALIDATION_FAILED;

        if (amount > sk.maxAmountPerTx) return SIG_VALIDATION_FAILED;

        // Push signer so executeBatch can enforce the daily limit.
        _skQueue[_skTail++] = signer;

        return _packValidationData(false, sk.validUntil, 0);
    }

    /// @notice Decodes executeBatch calldata, checks every call against the scope whitelist,
    /// verifies approve() spenders are whitelisted dests, and sums approve amounts.
    function _validateBatchScope(bytes calldata callData, address signer, uint256 gen)
        internal
        view
        returns (bool ok, uint256 totalApproved)
    {
        (address[] memory dests,, bytes[] memory datas) =
            abi.decode(callData[4:], (address[], uint256[], bytes[]));

        // If there's a mismatch in lengths, will cause a out-of-bounds error.
        if (dests.length != datas.length) return (false, 0);

        if (dests.length == 0) return (false, 0);

        for (uint256 i = 0; i < dests.length; i++) {
            if (!skAllowedDests[signer][gen][dests[i]]) return (false, 0);

            bytes memory d = datas[i];
            if (d.length < 4) return (false, 0);

            bytes4 sel;
            assembly { sel := mload(add(d, 32)) }

            if (!skAllowedSelectors[signer][gen][sel]) return (false, 0);

            if (sel == APPROVE_SELECTOR && d.length >= 68) {
                // The approve() spender (first argument, ABI-encoded at bytes 4-35) must itself
                // be a whitelisted dest - prevents approving arbitrary addresses.
                // Memory layout of bytes memory d: [length 32B][selector 4B][spender 32B][amount 32B]
                // So spender word is at d+32+4 = d+36.
                address spender;
                assembly { spender := mload(add(d, 36)) }
                if (!skAllowedDests[signer][gen][spender]) return (false, 0);

                uint256 amt;
                assembly { amt := mload(add(d, 68)) }
                totalApproved += amt;
            }
        }

        ok = true;
    }

    /// @notice Sums approve(address,uint256) amounts from the raw datas[] array.
    /// Used in executeBatch (execution phase) where calldata is already decoded.
    function _sumApprovals(bytes[] calldata datas) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < datas.length; i++) {
            if (datas[i].length < 68) continue;
            bytes4 sel = bytes4(datas[i][:4]);
            if (sel != APPROVE_SELECTOR) continue;
            total += uint256(bytes32(datas[i][36:68]));
        }
    }

    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            (success);
        }
    }

    /////////////////////
    // Session Key Management
    /////////////////////

    /// @notice Adds or replaces a session key with a spending limit and a scope whitelist.
    /// Bumping skGeneration invalidates any previous scope without deleting mappings.
    function addSessionKey(
        address key,
        SessionKeyData calldata params,
        address[] calldata allowedDests,
        bytes4[] calldata allowedSelectors
    ) external onlyOwner {
        if (key == address(0) || key == owner()) revert SmartWallet__InvalidSessionKey();
        sessionKeys[key] = params;
        sessionKeys[key].isActive = true;

        uint256 gen = ++skGeneration[key];
        for (uint256 i = 0; i < allowedDests.length; i++) {
            skAllowedDests[key][gen][allowedDests[i]] = true;
        }
        for (uint256 i = 0; i < allowedSelectors.length; i++) {
            skAllowedSelectors[key][gen][allowedSelectors[i]] = true;
        }

        emit SessionKeyAdded(key, params.validUntil);
    }

    function revokeSessionKey(address key) external onlyOwner {
        sessionKeys[key].isActive = false;
        emit SessionKeyRevoked(key);
    }

    /////////////////////
    // Getters
    /////////////////////

    function getEntryPoint() external view returns (address) {
        return address(i_entryPoint);
    }

    function getSessionKey(address key) external view returns (SessionKeyData memory) {
        return sessionKeys[key];
    }

    function getSessionKeyDailySpent(address key, uint256 day) external view returns (uint256) {
        return skDailySpent[key][day];
    }
}

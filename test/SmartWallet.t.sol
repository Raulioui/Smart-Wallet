// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SmartWallet} from "../src/SmartWallet.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SmartWalletTest is Test {
    SmartWallet wallet;
    MockERC20 usdc;
    MockERC20 weth;

    address entryPoint;
    uint256 ownerKey = 0xA11CE;
    address owner;
    uint256 executorKey = 0xB0B;
    address executor;

    function setUp() public {
        owner = vm.addr(ownerKey);
        executor = vm.addr(executorKey);
        entryPoint = makeAddr("entryPoint");

        wallet = new SmartWallet(entryPoint, owner);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
    }

    function _buildUserOp(bytes memory sig) internal view returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: address(wallet),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: sig
        });
    }

    function _sign(uint256 privateKey, bytes32 userOpHash) internal pure returns (bytes memory) {
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _addSessionKey(address key, uint48 validUntil) internal {
        SmartWallet.SessionKeyData memory params = SmartWallet.SessionKeyData({
            isActive: true,
            validUntil: validUntil,
            maxAmountPerTx: 500e6,
            dailyLimit: 1000e6
        });
        vm.prank(owner);
        wallet.addSessionKey(key, params);
    }

    /////////////////////
    // Constructor
    /////////////////////

    function test_Constructor() public view {
        assertEq(wallet.getEntryPoint(), entryPoint);
        assertEq(wallet.owner(), owner);
    }

    /////////////////////
    // Execute
    /////////////////////

    function test_OwnerCanExecute() public {
        usdc.mint(address(wallet), 100e6);
        address recipient = makeAddr("recipient");

        vm.prank(owner);
        wallet.execute(address(usdc), 0, abi.encodeWithSignature("transfer(address,uint256)", recipient, 100e6));

        assertEq(usdc.balanceOf(recipient), 100e6);
    }

    function test_EntryPointCanExecute() public {
        usdc.mint(address(wallet), 100e6);
        address recipient = makeAddr("recipient");

        vm.prank(entryPoint);
        wallet.execute(address(usdc), 0, abi.encodeWithSignature("transfer(address,uint256)", recipient, 100e6));

        assertEq(usdc.balanceOf(recipient), 100e6);
    }

    function test_UnauthorizedCannotExecute() public {
        vm.prank(makeAddr("hacker"));
        vm.expectRevert(SmartWallet.SmartWallet__NotFromEntryPointOrOwner.selector);
        wallet.execute(address(usdc), 0, "");
    }

    function test_Execute_RevertsIfCallFails() public {
        vm.prank(owner);
        vm.expectRevert();
        wallet.execute(address(usdc), 0, abi.encodeWithSignature("transfer(address,uint256)", makeAddr("r"), 100e6));
    }

    /////////////////////
    // Execute Batch
    /////////////////////

    function test_ExecuteBatch() public {
        usdc.mint(address(wallet), 200e6);
        address r1 = makeAddr("r1");
        address r2 = makeAddr("r2");

        address[] memory dests = new address[](2);
        dests[0] = address(usdc);
        dests[1] = address(usdc);

        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSignature("transfer(address,uint256)", r1, 100e6);
        datas[1] = abi.encodeWithSignature("transfer(address,uint256)", r2, 100e6);

        vm.prank(owner);
        wallet.executeBatch(dests, new uint256[](0), datas);

        assertEq(usdc.balanceOf(r1), 100e6);
        assertEq(usdc.balanceOf(r2), 100e6);
    }

    function test_ExecuteBatch_RevertsAtomically() public {
        // First call would succeed, second fails, both must revert
        usdc.mint(address(wallet), 100e6);
        address r1 = makeAddr("r1");

        address[] memory dests = new address[](2);
        dests[0] = address(usdc);
        dests[1] = address(usdc);

        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSignature("transfer(address,uint256)", r1, 100e6);
        datas[1] = abi.encodeWithSignature("transfer(address,uint256)", r1, 999e6); // no balance

        vm.prank(owner);
        vm.expectRevert();
        wallet.executeBatch(dests, new uint256[](0), datas);

        assertEq(usdc.balanceOf(r1), 0); // atomicity preserved
    }

    function test_ExecuteBatch_LengthMismatch() public {
        address[] memory dests = new address[](2);
        bytes[] memory datas = new bytes[](1); // mismatch

        vm.prank(owner);
        vm.expectRevert(SmartWallet.SmartWallet__ArrayLengthMismatch.selector);
        wallet.executeBatch(dests, new uint256[](0), datas);
    }

    /////////////////////
    // Session Keys
    /////////////////////

    function test_AddSessionKey() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        SmartWallet.SessionKeyData memory stored = wallet.getSessionKey(executor);
        assertEq(stored.isActive, true);
        assertEq(stored.validUntil, uint48(block.timestamp + 30 days));
        assertEq(stored.maxAmountPerTx, 500e6);
    }

    function test_NonOwnerCannotAddSessionKey() public {
        SmartWallet.SessionKeyData memory params = SmartWallet.SessionKeyData({
            isActive: true,
            validUntil: uint48(block.timestamp + 30 days),
            maxAmountPerTx: 500e6,
            dailyLimit: 1000e6
        });
        vm.prank(makeAddr("hacker"));
        vm.expectRevert();
        wallet.addSessionKey(executor, params);
    }

    function test_CannotAddOwnerAsSessionKey() public {
        SmartWallet.SessionKeyData memory params = SmartWallet.SessionKeyData({
            isActive: true,
            validUntil: uint48(block.timestamp + 30 days),
            maxAmountPerTx: 500e6,
            dailyLimit: 1000e6
        });
        vm.prank(owner);
        vm.expectRevert(SmartWallet.SmartWallet__InvalidSessionKey.selector);
        wallet.addSessionKey(owner, params);
    }

    function test_RevokeSessionKey() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        vm.prank(owner);
        wallet.revokeSessionKey(executor);

        assertEq(wallet.getSessionKey(executor).isActive, false);
    }

    function test_NonOwnerCannotRevokeSessionKey() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        vm.prank(makeAddr("hacker"));
        vm.expectRevert();
        wallet.revokeSessionKey(executor);
    }

    function test_ValidateUserOp_OwnerSignature() public {
        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(ownerKey, userOpHash));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);

        assertEq(result, 0); // SIG_VALIDATION_SUCCESS
    }

    function test_ValidateUserOp_WrongSignature() public {
        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(0xDEAD, userOpHash));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);

        assertEq(result, 1); // SIG_VALIDATION_FAILED
    }

    function test_ValidateUserOp_ValidSessionKey() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(executorKey, userOpHash));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);

        // Lower 160 bits = aggregator. 0 = signature valid, no aggregator needed.
        assertEq(address(uint160(result)), address(0));
    }

    function test_ValidateUserOp_RevokedSessionKey() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));
        vm.prank(owner);
        wallet.revokeSessionKey(executor);

        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(executorKey, userOpHash));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);

        assertEq(result, 1); // SIG_VALIDATION_FAILED
    }

    function test_ValidateUserOp_OnlyEntryPoint() public {
        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(ownerKey, userOpHash));

        vm.prank(makeAddr("hacker"));
        vm.expectRevert(SmartWallet.SmartWallet__NotFromEntryPoint.selector);
        wallet.validateUserOp(userOp, userOpHash, 0);
    }

    function test_CanReceiveEth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(wallet).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(wallet).balance, 1 ether);
    }

    function test_IsValidSignature_Owner() public view {
        bytes32 hash = keccak256("permit message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertEq(wallet.isValidSignature(hash, sig), bytes4(0x1626ba7e));
    }

    function test_IsValidSignature_ActiveSessionKey() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        bytes32 hash = keccak256("permit message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(executorKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertEq(wallet.isValidSignature(hash, sig), bytes4(0x1626ba7e));
    }

    function test_IsValidSignature_ExpiredSessionKey() public {
        uint48 validUntil = uint48(block.timestamp + 1 days);
        _addSessionKey(executor, validUntil);

        vm.warp(block.timestamp + 2 days);

        bytes32 hash = keccak256("permit message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(executorKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertEq(wallet.isValidSignature(hash, sig), bytes4(0xffffffff));
    }

    function test_IsValidSignature_RevokedSessionKey() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));
        vm.prank(owner);
        wallet.revokeSessionKey(executor);

        bytes32 hash = keccak256("permit message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(executorKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertEq(wallet.isValidSignature(hash, sig), bytes4(0xffffffff));
    }

    function test_IsValidSignature_UnknownSigner() public view {
        bytes32 hash = keccak256("permit message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xDEAD, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertEq(wallet.isValidSignature(hash, sig), bytes4(0xffffffff));
    }
}

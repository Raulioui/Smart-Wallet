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

    bytes4 constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));

    function _addSessionKey(address key, uint48 validUntil) internal {
        SmartWallet.SessionKeyData memory params = SmartWallet.SessionKeyData({
            isActive: true,
            validUntil: validUntil,
            maxAmountPerTx: 500e6,
            dailyLimit: 1000e6
        });
        // allowedDests includes usdc (token) and 0xBEEF (mock swap router used as approve target in tests)
        address[] memory allowedDests = new address[](2);
        allowedDests[0] = address(usdc);
        allowedDests[1] = address(0xBEEF);
        bytes4[] memory allowedSelectors = new bytes4[](1);
        allowedSelectors[0] = APPROVE_SELECTOR;
        vm.prank(owner);
        wallet.addSessionKey(key, params, allowedDests, allowedSelectors);
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
        address[] memory dests = new address[](0);
        bytes4[] memory sels = new bytes4[](0);
        vm.prank(makeAddr("hacker"));
        vm.expectRevert();
        wallet.addSessionKey(executor, params, dests, sels);
    }

    function test_CannotAddOwnerAsSessionKey() public {
        SmartWallet.SessionKeyData memory params = SmartWallet.SessionKeyData({
            isActive: true,
            validUntil: uint48(block.timestamp + 30 days),
            maxAmountPerTx: 500e6,
            dailyLimit: 1000e6
        });
        address[] memory dests = new address[](0);
        bytes4[] memory sels = new bytes4[](0);
        vm.prank(owner);
        vm.expectRevert(SmartWallet.SmartWallet__InvalidSessionKey.selector);
        wallet.addSessionKey(owner, params, dests, sels);
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

    function test_ValidateUserOp_DifferentLengths() public {
        (address user, uint256 userKey) = makeAddrAndKey("user");

        SmartWallet.SessionKeyData memory params = SmartWallet.SessionKeyData({
            isActive: true,
            validUntil: uint48(block.timestamp + 30 days),
            maxAmountPerTx: 500e6,
            dailyLimit: 1000e6
        });
        // allowedDests includes usdc (token) and 0xBEEF (mock swap router used as approve target in tests)
        address[] memory allowedDests = new address[](2);
        allowedDests[0] = address(usdc);
        allowedDests[1] = address(0xBEEF);
        bytes4[] memory allowedSelectors = new bytes4[](1);
        allowedSelectors[0] = APPROVE_SELECTOR;
        vm.prank(owner);
        wallet.addSessionKey(user, params, allowedDests, allowedSelectors);

        address[] memory dests = new address[](2);
        dests[0] = address(usdc);
        dests[1] = address(0xBEEF);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSignature("approve(address,uint256)", address(0xBEEF), 100e6);
        bytes32 userOpHash = keccak256("test");

        PackedUserOperation memory userOp = _buildUserOp(_sign(userKey, userOpHash));
        userOp.callData = abi.encodeCall(wallet.executeBatch, (dests, values, datas));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);

        assertEq(result, 1); // SIG_VALIDATION_Failed
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

        // Build executeBatch calldata: first call must be approve(spender, amount)
        address[] memory dests = new address[](1);
        dests[0] = address(usdc);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSignature("approve(address,uint256)", address(0xBEEF), 100e6);

        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(executorKey, userOpHash));
        userOp.callData = abi.encodeCall(wallet.executeBatch, (dests, values, datas));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);

        // Lower 160 bits = aggregator address. 0 means valid, no aggregator.
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

    function test_ValidateUserOp_Revert() public {
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

    function test_IsValidSignature_SessionKeyBlocked() public {
        // Session keys cannot sign arbitrary off-chain messages (Permit2, ERC-2612, etc.).
        // Blocking this prevents off-chain drains that bypass executeBatch scope checks.
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        bytes32 hash = keccak256("permit message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(executorKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertEq(wallet.isValidSignature(hash, sig), bytes4(0xffffffff));
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

    /////////////////////
    // Scope Enforcement
    /////////////////////

    function test_ValidateUserOp_RejectsNonWhitelistedDest() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        // weth is not in the scope whitelist — only usdc is
        address[] memory dests = new address[](1);
        dests[0] = address(weth);
        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSignature("approve(address,uint256)", address(0xBEEF), 100e6);

        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(executorKey, userOpHash));
        userOp.callData = abi.encodeCall(wallet.executeBatch, (dests, new uint256[](1), datas));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);
        assertEq(result, 1); // SIG_VALIDATION_FAILED
    }

    function test_ValidateUserOp_RejectsNonWhitelistedSelector() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        // transfer is not whitelisted — only approve is
        address[] memory dests = new address[](1);
        dests[0] = address(usdc);
        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSignature("transfer(address,uint256)", address(0xBEEF), 100e6);

        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(executorKey, userOpHash));
        userOp.callData = abi.encodeCall(wallet.executeBatch, (dests, new uint256[](1), datas));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);
        assertEq(result, 1); // SIG_VALIDATION_FAILED
    }

    function test_ValidateUserOp_RejectsExceedingPerTxLimit() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        // 600e6 > maxAmountPerTx (500e6)
        address[] memory dests = new address[](1);
        dests[0] = address(usdc);
        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSignature("approve(address,uint256)", address(0xBEEF), 600e6);

        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(executorKey, userOpHash));
        userOp.callData = abi.encodeCall(wallet.executeBatch, (dests, new uint256[](1), datas));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);
        assertEq(result, 1); // SIG_VALIDATION_FAILED
    }

    function test_ValidateUserOp_RejectsMultiApproveExceedingPerTxLimit() public {
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        // Two approves of 300e6 each = 600e6 > maxAmountPerTx (500e6).
        // Both must be summed — not just datas[0].
        address[] memory dests = new address[](2);
        dests[0] = address(usdc);
        dests[1] = address(usdc);
        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSignature("approve(address,uint256)", address(0xBEEF), 300e6);
        datas[1] = abi.encodeWithSignature("approve(address,uint256)", address(0xBEEF), 300e6);

        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(executorKey, userOpHash));
        userOp.callData = abi.encodeCall(wallet.executeBatch, (dests, new uint256[](2), datas));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);
        assertEq(result, 1); // SIG_VALIDATION_FAILED — 600e6 > 500e6
    }

    function test_ScopeInvalidatedAfterReAddSessionKey() public {
        // Add key with usdc in scope, then re-add with different scope (weth only).
        // Old generation's scope (usdc) must no longer be active.
        _addSessionKey(executor, uint48(block.timestamp + 30 days));

        SmartWallet.SessionKeyData memory newParams = SmartWallet.SessionKeyData({
            isActive: true,
            validUntil: uint48(block.timestamp + 30 days),
            maxAmountPerTx: 500e6,
            dailyLimit: 1000e6
        });
        address[] memory newDests = new address[](1);
        newDests[0] = address(weth);
        bytes4[] memory newSels = new bytes4[](1);
        newSels[0] = APPROVE_SELECTOR;
        vm.prank(owner);
        wallet.addSessionKey(executor, newParams, newDests, newSels);

        // usdc was valid under gen 1 but NOT under gen 2
        address[] memory dests = new address[](1);
        dests[0] = address(usdc);
        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSignature("approve(address,uint256)", address(0xBEEF), 100e6);

        bytes32 userOpHash = keccak256("test");
        PackedUserOperation memory userOp = _buildUserOp(_sign(executorKey, userOpHash));
        userOp.callData = abi.encodeCall(wallet.executeBatch, (dests, new uint256[](1), datas));

        vm.prank(entryPoint);
        uint256 result = wallet.validateUserOp(userOp, userOpHash, 0);
        assertEq(result, 1); // SIG_VALIDATION_FAILED — usdc not in new scope
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LambdaPay, TransferIntent} from "../contracts/LambdaPay.sol";
import {ILambdaPay, Permit2SignatureTransferData} from "../contracts/interfaces/ILambdaPay.sol";
import {IWrapped} from "../contracts/interfaces/IWrapped.sol";
import {Permit2} from "../contracts/permit2/Permit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC20Permit} from "./mocks/MockERC20Permit.sol";
import {MockWrapped} from "./mocks/MockWrapped.sol";
import {MockUniversalRouter} from "./mocks/MockUniversalRouter.sol";
import {ISignatureTransfer} from "../contracts/permit2/interfaces/ISignatureTransfer.sol";

/**
 * @title Permit2TransferTest
 * @dev Tests transferToken function that uses Permit2 for approvals
 */
contract Permit2TransferTest is Test {
    // Contract instances
    LambdaPay public lambdaPay;
    MockERC20 public token;
    MockWrapped public wrappedNative;
    Permit2 public permit2;
    MockUniversalRouter public mockRouter;

    // Test accounts
    address public operator;
    address public operatorFeeDestination;
    address public merchant;
    address public payer;
    uint256 public payerPrivateKey;

    // Constants
    uint256 public constant INITIAL_BALANCE = 100 ether;
    bytes32 public constant PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );
    bytes32 public constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    // Events to test
    event Transferred(
        address indexed operator,
        bytes16 indexed id,
        address indexed recipient,
        address sender,
        uint256 spentAmount,
        address spentCurrency,
        uint256 recipientAmount,
        address recipientCurrency
    );

    function setUp() public {
        // Create test accounts
        operator = makeAddr("operator");
        operatorFeeDestination = makeAddr("operatorFeeDestination");
        merchant = makeAddr("merchant");

        // Create a deterministic private key for payer
        payerPrivateKey = 0x1234;
        payer = vm.addr(payerPrivateKey);

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST", 18);
        wrappedNative = new MockWrapped();
        permit2 = new Permit2();
        mockRouter = new MockUniversalRouter(wrappedNative);

        // Deploy LambdaPay contract
        lambdaPay = new LambdaPay(
            IUniversalRouter(address(mockRouter)),
            permit2,
            operator,
            operatorFeeDestination,
            wrappedNative,
            "LambdaPay",
            "1"
        );

        // Fund test accounts
        vm.deal(payer, INITIAL_BALANCE);
        token.mint(payer, INITIAL_BALANCE);

        // Label addresses for better trace output
        vm.label(address(lambdaPay), "LambdaPay");
        vm.label(address(token), "TestToken");
        vm.label(address(permit2), "Permit2");
        vm.label(operator, "Operator");
        vm.label(operatorFeeDestination, "OperatorFeeDestination");
        vm.label(merchant, "Merchant");
        vm.label(payer, "Payer");
    }

    /**
     * @dev Tests transferToken function that uses Permit2 for approvals
     */
    function test_transferToken() public {
        // Setup transfer intent values
        uint256 recipientAmount = 0.5 ether;
        uint256 feeAmount = 0.01 ether;
        uint256 totalAmount = recipientAmount + feeAmount;
        bytes16 intentId = bytes16(keccak256("test-permit2-transfer"));
        uint256 deadline = block.timestamp + 1 hours;

        // Create private key for operator
        uint256 operatorPrivateKey = 1;
        address operatorWallet = vm.addr(operatorPrivateKey);

        // Register the operator wallet
        vm.startPrank(operatorWallet);
        lambdaPay.registerOperatorWithFeeDestination(operatorFeeDestination);
        vm.stopPrank();

        // Get initial balances
        uint256 initialPayerTokenBalance = token.balanceOf(payer);
        uint256 initialMerchantTokenBalance = token.balanceOf(merchant);
        uint256 initialFeeDestTokenBalance = token.balanceOf(operatorFeeDestination);

        // Create transfer intent
        TransferIntent memory intent = TransferIntent({
            recipientAmount: recipientAmount,
            deadline: deadline,
            recipient: payable(merchant),
            recipientCurrency: address(token),
            refundDestination: payable(payer),
            feeAmount: feeAmount,
            id: intentId,
            operator: operatorWallet,
            signature: bytes(""),
            prefix: bytes("")
        });

        // Sign the intent
        intent.signature = _signIntent(intent, operatorPrivateKey, payer);

        // Approve token in Permit2
        vm.startPrank(payer);
        token.approve(address(permit2), type(uint256).max);
        vm.stopPrank();

        // Create Permit2 signature data
        uint256 nonce = 0; // First nonce for this token/owner/spender
        uint256 permit2Deadline = block.timestamp + 1 hours;

        // Create the permitTransferFrom data
        ISignatureTransfer.PermitTransferFrom memory permitData = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(token), amount: totalAmount}),
            nonce: nonce,
            deadline: permit2Deadline
        });

        // Create transfer details
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: address(lambdaPay), requestedAmount: totalAmount});

        // Sign the Permit2 message
        bytes memory permit2Signature = _signPermit2(permitData, address(lambdaPay), payerPrivateKey);

        // Prepare the Permit2SignatureTransferData
        Permit2SignatureTransferData memory signatureTransferData = Permit2SignatureTransferData({
            permit: permitData,
            transferDetails: transferDetails,
            signature: permit2Signature
        });

        // Execute the transfer using Permit2
        vm.startPrank(payer);

        // Expect Transferred event
        vm.expectEmit(true, true, true, true, address(lambdaPay));
        emit Transferred(
            operatorWallet, intentId, merchant, payer, totalAmount, address(token), recipientAmount, address(token)
        );

        lambdaPay.transferToken(intent, signatureTransferData);
        vm.stopPrank();

        // Check balances after transfer
        assertEq(token.balanceOf(payer), initialPayerTokenBalance - totalAmount, "Payer token balance incorrect");
        assertEq(
            token.balanceOf(merchant), initialMerchantTokenBalance + recipientAmount, "Merchant token balance incorrect"
        );
        assertEq(
            token.balanceOf(operatorFeeDestination),
            initialFeeDestTokenBalance + feeAmount,
            "Fee destination token balance incorrect"
        );

        // Verify the intent is marked as processed
        assertTrue(lambdaPay.processedTransferIntents(operatorWallet, intentId), "Intent not marked as processed");
    }

    /**
     * @dev Tests that transferToken reverts when the recipient currency doesn't match the token
     */
    function test_revertWhen_incorrectCurrency() public {
        // Setup transfer intent values
        uint256 recipientAmount = 0.5 ether;
        uint256 feeAmount = 0.01 ether;
        uint256 totalAmount = recipientAmount + feeAmount;
        bytes16 intentId = bytes16(keccak256("test-permit2-incorrect-currency"));
        uint256 deadline = block.timestamp + 1 hours;

        // Create private key for operator
        uint256 operatorPrivateKey = 1;
        address operatorWallet = vm.addr(operatorPrivateKey);

        // Register the operator wallet
        vm.startPrank(operatorWallet);
        lambdaPay.registerOperatorWithFeeDestination(operatorFeeDestination);
        vm.stopPrank();

        // Create transfer intent with incorrect currency (address(0) instead of token)
        TransferIntent memory intent = TransferIntent({
            recipientAmount: recipientAmount,
            deadline: deadline,
            recipient: payable(merchant),
            recipientCurrency: address(0), // This is native currency, not the token
            refundDestination: payable(payer),
            feeAmount: feeAmount,
            id: intentId,
            operator: operatorWallet,
            signature: bytes(""),
            prefix: bytes("")
        });

        // Sign the intent
        intent.signature = _signIntent(intent, operatorPrivateKey, payer);

        // Approve token in Permit2
        vm.startPrank(payer);
        token.approve(address(permit2), type(uint256).max);
        vm.stopPrank();

        // Create Permit2 signature data
        uint256 nonce = 0;
        uint256 permit2Deadline = block.timestamp + 1 hours;

        ISignatureTransfer.PermitTransferFrom memory permitData = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(token), amount: totalAmount}),
            nonce: nonce,
            deadline: permit2Deadline
        });

        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: address(lambdaPay), requestedAmount: totalAmount});

        bytes memory permit2Signature = _signPermit2(permitData, address(lambdaPay), payerPrivateKey);

        Permit2SignatureTransferData memory signatureTransferData = Permit2SignatureTransferData({
            permit: permitData,
            transferDetails: transferDetails,
            signature: permit2Signature
        });

        // Execute the transfer and expect it to revert
        vm.startPrank(payer);
        vm.expectRevert(abi.encodeWithSelector(ILambdaPay.IncorrectCurrency.selector, address(token)));
        lambdaPay.transferToken(intent, signatureTransferData);
        vm.stopPrank();
    }

    /**
     * @dev Tests that transferToken reverts when the transfer details are invalid
     */
    function test_revertWhen_invalidTransferDetails() public {
        // Setup transfer intent values
        uint256 recipientAmount = 0.5 ether;
        uint256 feeAmount = 0.01 ether;
        uint256 totalAmount = recipientAmount + feeAmount;
        bytes16 intentId = bytes16(keccak256("test-permit2-invalid-details"));
        uint256 deadline = block.timestamp + 1 hours;

        // Create private key for operator
        uint256 operatorPrivateKey = 1;
        address operatorWallet = vm.addr(operatorPrivateKey);

        // Register the operator wallet
        vm.startPrank(operatorWallet);
        lambdaPay.registerOperatorWithFeeDestination(operatorFeeDestination);
        vm.stopPrank();

        // Create transfer intent
        TransferIntent memory intent = TransferIntent({
            recipientAmount: recipientAmount,
            deadline: deadline,
            recipient: payable(merchant),
            recipientCurrency: address(token),
            refundDestination: payable(payer),
            feeAmount: feeAmount,
            id: intentId,
            operator: operatorWallet,
            signature: bytes(""),
            prefix: bytes("")
        });

        // Sign the intent
        intent.signature = _signIntent(intent, operatorPrivateKey, payer);

        // Approve token in Permit2
        vm.startPrank(payer);
        token.approve(address(permit2), type(uint256).max);
        vm.stopPrank();

        // Create Permit2 signature data with WRONG transfer details
        uint256 nonce = 0;
        uint256 permit2Deadline = block.timestamp + 1 hours;

        ISignatureTransfer.PermitTransferFrom memory permitData = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(token), amount: totalAmount}),
            nonce: nonce,
            deadline: permit2Deadline
        });

        // Wrong recipient in transfer details (merchant instead of lambdaPay)
        ISignatureTransfer.SignatureTransferDetails memory transferDetails = ISignatureTransfer.SignatureTransferDetails({
            to: merchant, // WRONG - should be address(lambdaPay)
            requestedAmount: totalAmount
        });

        bytes memory permit2Signature = _signPermit2(permitData, address(lambdaPay), payerPrivateKey);

        Permit2SignatureTransferData memory signatureTransferData = Permit2SignatureTransferData({
            permit: permitData,
            transferDetails: transferDetails,
            signature: permit2Signature
        });

        // Execute the transfer and expect it to revert
        vm.startPrank(payer);
        vm.expectRevert(ILambdaPay.InvalidTransferDetails.selector);
        lambdaPay.transferToken(intent, signatureTransferData);
        vm.stopPrank();
    }

    /**
     * @dev Helper function to sign a TransferIntent with a private key
     * @param _intent The transfer intent to sign
     * @param _privateKey The private key to sign with
     * @param _sender The sender address who will execute the payment
     * @return The ECDSA signature as bytes
     */
    function _signIntent(TransferIntent memory _intent, uint256 _privateKey, address _sender)
        internal
        view
        returns (bytes memory)
    {
        // Generate EIP-712 signature
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("LambdaPay")),
                keccak256(bytes("1")),
                block.chainid,
                address(lambdaPay)
            )
        );

        bytes32 transferIntentTypehash = 0x1a1aabfa4cece8a00c61cb6de3d4d4fad1ab30e1f6c2f67eba017585d9b0bf73;

        bytes32 structHash = keccak256(
            abi.encode(
                transferIntentTypehash,
                _intent.recipientAmount,
                _intent.deadline,
                _intent.recipient,
                _intent.recipientCurrency,
                _intent.refundDestination,
                _intent.feeAmount,
                _intent.id,
                _intent.operator,
                _sender,
                address(lambdaPay),
                keccak256(_intent.prefix)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @dev Helper function to sign a Permit2 message
     * @param _permit The Permit2 data
     * @param _spender The spender address (LambdaPay contract)
     * @param _privateKey The private key to sign with
     * @return The ECDSA signature as bytes
     */
    function _signPermit2(ISignatureTransfer.PermitTransferFrom memory _permit, address _spender, uint256 _privateKey)
        internal
        view
        returns (bytes memory)
    {
        // Generate EIP-712 signature for Permit2
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Permit2")),
                block.chainid,
                address(permit2)
            )
        );

        bytes32 tokenPermissionsHash =
            keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, _permit.permitted.token, _permit.permitted.amount));

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissionsHash, _spender, _permit.nonce, _permit.deadline)
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}

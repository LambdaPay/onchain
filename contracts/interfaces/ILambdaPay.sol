// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import necessary interfaces, especially for structs used across contracts
import {ISignatureTransfer} from "@lambdapay/onchain/contracts/permit2/interfaces/ISignatureTransfer.sol";

/**
 * @notice Defines the structure for a transfer operation authorized by an operator.
 * @dev The signature field uses EIP-712 signing based on the LambdaPay contract's domain separator and type hash.
 *      The hash includes all other struct members, chainId, sender address, and the LambdaPay contract address.
 *      The prefix allows for optional deviation from standard EIP-712 signing if needed, though standard EIP-712 is preferred.
 * @param recipientAmount Amount of currency to transfer to the primary recipient.
 * @param deadline Unix timestamp by which the transfer must be included in a block.
 * @param recipient The address which will receive the `recipientAmount`.
 * @param recipientCurrency The currency address (`address(0)` for native) that `recipientAmount` and `feeAmount` are denominated in.
 * @param refundDestination The address which will receive swap refunds. If set to `address(0)`, refunds go to the payer (`msg.sender`).
 * @param feeAmount The fee amount (in `recipientCurrency`) to send to the operator's fee destination.
 * @param id A unique identifier (e.g., UUID bytes) for the transfer intent, used to prevent replays per operator.
 * @param operator The address authorized (via signature) to initiate this transfer intent. Must be registered.
 * @param signature An EIP-712 signature (or custom prefixed signature) from the `operator` authorizing this intent.
 * @param prefix An optional byte string prepended to the hash before signing (if non-empty, deviates from standard EIP-712).
 */
struct TransferIntent {
    uint256 recipientAmount;
    uint256 deadline;
    address payable recipient;
    address recipientCurrency;
    address refundDestination;
    uint256 feeAmount;
    bytes16 id;
    address operator;
    bytes signature;
    bytes prefix;
}

/**
 * @notice Bundles data required for a Permit2 signature-based transfer.
 * @param permit The PermitTransferFrom struct containing token details and nonce.
 * @param transferDetails The SignatureTransferDetails struct containing recipient and amount for the Permit2 transfer.
 * @param signature The EIP-712 signature from the token owner authorizing the Permit2 operation.
 */
struct Permit2SignatureTransferData {
    ISignatureTransfer.PermitTransferFrom permit;
    ISignatureTransfer.SignatureTransferDetails transferDetails;
    bytes signature;
}

/**
 * @notice Bundles data required for an EIP-2612 (or compatible) permit-based transfer, often used for subsidized/gasless approvals.
 * @param owner The address of the token owner whose funds are being permitted and spent.
 * @param signature The EIP-2612 signature (containing v, r, s) from the `owner` authorizing the spend.
 */
struct EIP2612SignatureTransferData {
    address owner;
    bytes signature;
}

/**
 * @title ILambdaPay Interface
 * @notice Defines the external functions for executing various types of transfers, potentially involving swaps,
 *         wrapping/unwrapping, and different approval mechanisms (Permit2, EIP-2612, pre-approved).
 * @dev This interface focuses on the user-facing transfer operations. Administrative functions
 *      (like operator registration, pausing) are typically managed directly on the implementation contract.
 */
interface ILambdaPay {
    // --- Events ---

    /**
     * @notice Emitted when a transfer intent is successfully processed and funds are distributed.
     * @param operator The operator address that authorized the intent.
     * @param id The unique ID of the processed transfer intent.
     * @param recipient The primary recipient of the funds.
     * @param sender The address that initiated the transaction and/or provided the input funds (payer).
     * @param spentAmount The total amount of the input currency consumed by the operation (including fees and swap costs).
     * @param spentCurrency The address of the input currency provided by the sender (`address(0)` for native).
     * @param recipientAmount The amount actually sent to the primary recipient.
     * @param recipientCurrency The currency sent to the primary recipient.
     */
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

    /**
     * @notice Emitted when an operator is registered or their fee destination is updated via admin functions.
     * @param operator The operator address.
     * @param feeDestination The address where fees for this operator will be sent.
     */
    event OperatorRegistered(address indexed operator, address feeDestination);

    /**
     * @notice Emitted when an operator is unregistered via admin functions.
     * @param operator The operator address that was unregistered.
     */
    event OperatorUnregistered(address indexed operator);

    // --- Errors ---

    /**
     * @notice Reverts when a required native currency transfer (e.g., to recipient, fee destination, or refund) fails.
     * @param destination The address the native currency transfer was intended for.
     * @param amount The amount of native currency that failed to send.
     * @param isRefund Indicates if the failed transfer was part of a refund process.
     * @param data Additional data returned from the failed low-level call, if any.
     */
    error NativeTransferFailed(address destination, uint256 amount, bool isRefund, bytes data);

    /// @notice Reverts if the `operator` specified in the `TransferIntent` is not registered.
    error OperatorNotRegistered();

    /// @notice Reverts if the `signature` in the `TransferIntent` is invalid or does not recover to the `operator`.
    error InvalidSignature();

    /**
     * @notice Reverts if the `msg.value` sent with a native currency payment does not exactly match the required amount.
     * @param difference The difference between `msg.value` and the required amount (`recipientAmount + feeAmount`).
     *                   Positive if too much was sent, negative if too little.
     */
    error InvalidNativeAmount(int256 difference);

    /**
     * @notice Reverts if the payer (or owner in subsidized transfers) does not have a sufficient balance of the required token.
     * @param shortfall The amount of additional tokens required.
     */
    error InsufficientBalance(uint256 shortfall);

    /**
     * @notice Reverts if the required ERC20 allowance (either to this contract or Permit2) is insufficient.
     * @param shortfall The amount of additional allowance required.
     */
    error InsufficientAllowance(uint256 shortfall);

    /**
     * @notice Reverts if the `recipientCurrency` in the intent is incompatible with the chosen transfer function
     *         (e.g., providing a token address to `transferNative`, or native address to `transferToken`).
     * @param providedCurrency The currency specified in the intent or implicitly used by the function.
     */
    error IncorrectCurrency(address providedCurrency);

    /**
     * @notice Reverts if the details within `Permit2SignatureTransferData.transferDetails` (like recipient or amount)
     *         do not match the requirements of the `TransferIntent` or the called function.
     */
    error InvalidTransferDetails();

    /// @notice Reverts if `block.timestamp` is greater than or equal to the `deadline` in the `TransferIntent`.
    error ExpiredIntent();

    /// @notice Reverts if `recipient` in the `TransferIntent` is `address(0)`.
    error NullRecipient();

    /// @notice Reverts if a `TransferIntent` with the same `operator` and `id` has already been processed.
    error AlreadyProcessed();

    /**
     * @notice Reverts when an ERC20 transfer (in or out) does not result in the expected balance change,
     *         typically indicating a fee-on-transfer token or other non-standard behavior.
     * @param token The address of the ERC20 token.
     * @param target The address whose balance change was incorrect.
     * @param expectedChange The expected increase in the target's balance.
     * @param actualChange The actual increase observed in the target's balance.
     */
    error InexactTransfer(address token, address target, uint256 expectedChange, uint256 actualChange);

    /**
     * @notice Reverts when a Uniswap swap fails, providing the reason string if available.
     * @param reason The error reason string returned by Uniswap or related contracts.
     */
    error SwapFailedString(string reason);

    /**
     * @notice Reverts when a Uniswap swap fails, providing the raw error bytes if a string reason is not available.
     * @param data The raw error data returned by Uniswap or related contracts.
     */
    error SwapFailedBytes(bytes data);

    /**
     * @notice Reverts if the `permit` call in `subsidizedTransferToken` fails, either by reverting
     *         or by not incrementing the nonce (indicating a non-compliant or non-existent implementation).
     */
    error PermitCallFailed();

    // --- Transfer Functions ---

    /**
     * @notice Sends the exact amount of native currency (`msg.value`) from the sender (`msg.sender`) to the recipient and fee destination specified in the intent.
     * @dev Requires `_intent.recipientCurrency == address(0)`.
     *      `msg.value` must exactly equal `_intent.recipientAmount + _intent.feeAmount`.
     * @param _intent The `TransferIntent` struct containing details and operator signature.
     */
    function transferNative(TransferIntent calldata _intent) external payable;

    /**
     * @notice Transfers the exact amount of an ERC20 token from the sender (`msg.sender`) to the recipient and fee destination, using a Permit2 signature for approval.
     * @dev Requires `_intent.recipientCurrency == _signatureTransferData.permit.permitted.token`.
     *      Requires sender to have approved Permit2 contract for the token.
     *      Requires `_signatureTransferData.transferDetails.to == address(this)` and `requestedAmount == _intent.recipientAmount + _intent.feeAmount`.
     * @param _intent The `TransferIntent` struct containing details and operator signature.
     * @param _signatureTransferData Permit2 data including the permit, transfer details, and owner's signature.
     */
    function transferToken(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData
    ) external;

    /**
     * @notice Transfers the exact amount of an ERC20 token from the sender (`msg.sender`) to the recipient and fee destination, using a standard ERC20 pre-approval (`approve`).
     * @dev Requires `_intent.recipientCurrency` to be the target token address (`!= address(0)`).
     *      Requires sender to have approved this contract for at least `_intent.recipientAmount + _intent.feeAmount` of the token.
     * @param _intent The `TransferIntent` struct containing details and operator signature.
     */
    function transferTokenPreApproved(TransferIntent calldata _intent) external;

    /**
     * @notice Receives native currency (`msg.value`), wraps it into the canonical wrapped token (e.g., WETH), and transfers the wrapped token to the recipient and fee destination.
     * @dev Requires `_intent.recipientCurrency == address(wrappedToken)`.
     *      `msg.value` must exactly equal `_intent.recipientAmount + _intent.feeAmount`.
     * @param _intent The `TransferIntent` struct containing details and operator signature.
     */
    function wrapAndTransfer(TransferIntent calldata _intent) external payable;

    /**
     * @notice Transfers the canonical wrapped token (e.g., WETH) from the sender (`msg.sender`) to this contract using Permit2, unwraps it, and sends native currency to the recipient and fee destination.
     * @dev Requires `_intent.recipientCurrency == address(0)`.
     *      Requires `_signatureTransferData.permit.permitted.token == address(wrappedToken)`.
     *      Requires sender to have approved Permit2 contract for the wrapped token.
     *      Requires `_signatureTransferData.transferDetails.to == address(this)` and `requestedAmount == _intent.recipientAmount + _intent.feeAmount`.
     * @param _intent The `TransferIntent` struct containing details and operator signature.
     * @param _signatureTransferData Permit2 data for the wrapped token transfer.
     */
    function unwrapAndTransfer(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData
    ) external;

    /**
     * @notice Transfers the canonical wrapped token (e.g., WETH) from the sender (`msg.sender`) to this contract using standard ERC20 pre-approval, unwraps it, and sends native currency to the recipient and fee destination.
     * @dev Requires `_intent.recipientCurrency == address(0)`.
     *      Requires sender to have approved this contract for at least `_intent.recipientAmount + _intent.feeAmount` of the wrapped token.
     * @param _intent The `TransferIntent` struct containing details and operator signature.
     */
    function unwrapAndTransferPreApproved(TransferIntent calldata _intent) external;

    /**
     * @notice Receives native currency (`msg.value`), swaps it via Uniswap V3 for the `_intent.recipientCurrency`, and transfers the resulting token to the recipient and fee destination. Refunds unused native currency to the sender.
     * @dev Requires `_intent.recipientCurrency` to be a token address (`!= address(0)` and `!= address(wrappedToken)`).
     *      `msg.value` should be the maximum native amount the sender is willing to spend on the swap.
     *      The swap aims for an exact output amount (`_intent.recipientAmount + _intent.feeAmount`). Reverts if `msg.value` is insufficient.
     * @param _intent The `TransferIntent` struct containing details and operator signature.
     * @param poolFeesTier The Uniswap V3 pool fee tier (e.g., 3000 for 0.3%) for the swap path involving WETH.
     */
    function swapAndTransferUniswapV3Native(TransferIntent calldata _intent, uint24 poolFeesTier) external payable;

    /**
     * @notice Transfers an ERC20 token from the sender (`msg.sender`) to this contract via Permit2, swaps it via Uniswap V3 for `_intent.recipientCurrency`, and transfers the resulting currency (token or native) to the recipient and fee destination. Refunds unused input token to the sender.
     * @dev Requires `_intent.recipientCurrency != _signatureTransferData.permit.permitted.token`.
     *      Requires sender to have approved Permit2 contract for the input token.
     *      Requires `_signatureTransferData.transferDetails.to == address(this)`. `requestedAmount` is the max input token amount.
     *      The swap aims for an exact output amount (`_intent.recipientAmount + _intent.feeAmount`). Reverts if `requestedAmount` is insufficient.
     * @param _intent The `TransferIntent` struct containing details and operator signature.
     * @param _signatureTransferData Permit2 data for the input token transfer.
     * @param poolFeesTier The Uniswap V3 pool fee tier for the swap path.
     */
    function swapAndTransferUniswapV3Token(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData,
        uint24 poolFeesTier
    ) external;

    /**
     * @notice Transfers an ERC20 token (`_tokenIn`) from the sender (`msg.sender`) to this contract via standard ERC20 pre-approval, swaps it via Uniswap V3 for `_intent.recipientCurrency`, and transfers the resulting currency (token or native) to the recipient and fee destination. Refunds unused input token to the sender.
     * @dev Requires `_intent.recipientCurrency != _tokenIn`.
     *      Requires sender to have approved this contract for at least `maxWillingToPay` of `_tokenIn`.
     *      The swap aims for an exact output amount (`_intent.recipientAmount + _intent.feeAmount`). Reverts if `maxWillingToPay` is insufficient.
     * @param _intent The `TransferIntent` struct containing details and operator signature.
     * @param _tokenIn The address of the ERC20 token the sender is paying with.
     * @param maxWillingToPay The maximum amount of `_tokenIn` the sender is willing to provide for the swap.
     * @param poolFeesTier The Uniswap V3 pool fee tier for the swap path.
     */
    function swapAndTransferUniswapV3TokenPreApproved(
        TransferIntent calldata _intent,
        address _tokenIn,
        uint256 maxWillingToPay,
        uint24 poolFeesTier
    ) external;

    /**
     * @notice Uses an EIP-2612 permit signature to gain approval for a token transfer from the `owner`'s account, then transfers the token to the recipient and fee destination. The transaction fee (`gas`) is paid by `msg.sender`.
     * @dev Requires `_intent.recipientCurrency` to be the token address (`!= address(0)`).
     *      The `sender` for the `TransferIntent` signature validation is `_signatureTransferData.owner`.
     *      Relies on the target token implementing EIP-2612 `permit` correctly.
     * @param _intent The `TransferIntent` struct containing details and operator signature.
     * @param _signatureTransferData EIP-2612 permit data including the owner and their signature.
     */
    function subsidizedTransferToken(
        TransferIntent calldata _intent,
        EIP2612SignatureTransferData calldata _signatureTransferData
    ) external;
}

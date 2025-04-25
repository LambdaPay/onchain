// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// openzeppelin
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
// uniswap
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {Constants} from "@uniswap/universal-router/contracts/libraries/Constants.sol";
// lambdapay
import {IWrapped} from "@lambdapay/onchain/contracts/interfaces/IWrapped.sol";
import {IERC7597} from "@lambdapay/onchain/contracts/interfaces/IERC7597.sol";
import {Sweepable} from "@lambdapay/onchain/contracts/utils/Sweepable.sol";
import {Permit2} from "@lambdapay/onchain/contracts/permit2/Permit2.sol";
import {
    ILambdaPay,
    TransferIntent,
    Permit2SignatureTransferData,
    EIP2612SignatureTransferData
} from "@lambdapay/onchain/contracts/interfaces/ILambdaPay.sol";

// Uniswap error selectors, used to surface information when swaps fail
// Pulled from @uniswap/universal-router/out/V3SwapRouter.sol/V3SwapRouter.json after compiling with forge
bytes32 constant V3_INVALID_SWAP = keccak256(hex"316cf0eb");
bytes32 constant V3_TOO_LITTLE_RECEIVED = keccak256(hex"39d35496");
bytes32 constant V3_TOO_MUCH_REQUESTED = keccak256(hex"739dbe52");
bytes32 constant V3_INVALID_AMOUNT_OUT = keccak256(hex"d4e0248e");
bytes32 constant V3_INVALID_CALLER = keccak256(hex"32b13d91");

/**
 * @title LambdaPay Contract
 * @author LambdaPay Team
 * @notice Handles various types of token and native currency transfers, including swaps via Uniswap V3,
 * using Permit2 signatures, EIP-2612 permits, and standard approvals. It incorporates operator
 * signature validation for transfer intents and supports operator fees.
 * @dev Inherits OpenZeppelin contracts for security (Pausable, ReentrancyGuard, Ownable),
 * utilities (SafeERC20, ECDSA, EIP712), and interacts with Uniswap Universal Router, Permit2,
 * and a wrapped native currency contract. Implements ILambdaPay and Sweepable interfaces.
 * Uses EIP-712 for signing transfer intents.
 */
contract LambdaPay is Context, Ownable(msg.sender), Pausable, ReentrancyGuard, Sweepable, EIP712, ILambdaPay {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWrapped;

    // --- State Variables ---

    /**
     * @notice Map of operator addresses to their designated fee destination addresses.
     * @dev Only registered operators (keys in this map) can authorize transfers.
     */
    mapping(address => address) public feeDestinations;

    /**
     * @notice Map tracking processed transfer intents to prevent replay attacks.
     * @dev Structure: operator => intentId => processed (true/false)
     */
    mapping(address => mapping(bytes16 => bool)) public processedTransferIntents;

    /**
     * @notice Represents the native token of the chain (e.g., ETH, MATIC) using address(0).
     */
    address private constant NATIVE_CURRENCY = address(0);

    /**
     * @notice The Uniswap Universal Router contract instance for executing swaps.
     */
    IUniversalRouter public immutable uniswap;

    /**
     * @notice The Uniswap Permit2 contract instance for handling signature-based approvals.
     * @dev See: https://github.com/Uniswap/permit2
     */
    Permit2 public immutable permit2;

    /**
     * @notice The canonical wrapped native token contract instance for this chain (e.g., WETH, WMATIC).
     */
    IWrapped public immutable wrapped;

    // --- EIP-712 Setup ---

    // --- EIP-712 Typehash ---
    // keccak256("TransferIntent(uint256 recipientAmount,uint256 deadline,address recipient,address recipientCurrency,address refundDestination,uint256 feeAmount,bytes16 id,address operator,address sender,address contractAddress,bytes prefix)")
    bytes32 private constant TRANSFER_INTENT_TYPEHASH =
        0x1a1aabfa4cece8a00c61cb6de3d4d4fad1ab30e1f6c2f67eba017585d9b0bf73;

    // --- Constructor ---

    /**
     * @param _uniswap The address of the Uniswap Universal Router.
     * @param _permit2 The address of the Permit2 contract.
     * @param _initialOperator An initial operator address allowed to process payments.
     * @param _initialFeeDestination The fee destination for the initial operator.
     * @param _wrapped The address of the canonical wrapped native token contract.
     * @param _eip712Name The EIP-712 domain name (e.g., "LambdaPay").
     * @param _eip712Version The EIP-712 domain version (e.g., "1").
     */
    constructor(
        IUniversalRouter _uniswap,
        Permit2 _permit2,
        address _initialOperator,
        address _initialFeeDestination,
        IWrapped _wrapped,
        string memory _eip712Name,
        string memory _eip712Version
    ) EIP712(_eip712Name, _eip712Version) {
        require(
            address(_uniswap) != address(0) && address(_permit2) != address(0) && address(_wrapped) != address(0)
                && _initialOperator != address(0) && _initialFeeDestination != address(0),
            "LambdaPay: INVALID_CONSTRUCTOR_PARAMS"
        );
        uniswap = _uniswap;
        permit2 = _permit2;
        wrapped = _wrapped;

        feeDestinations[_initialOperator] = _initialFeeDestination;
        emit OperatorRegistered(_initialOperator, _initialFeeDestination);
    }

    // --- Modifiers ---

    /**
     * @dev Validates the transfer intent signature, deadline, recipient, and checks for replays.
     * @param _intent The TransferIntent data structure.
     * @param sender The address initiating the transfer (payer or subsidized owner).
     */
    modifier validIntent(TransferIntent calldata _intent, address sender) {
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_INTENT_TYPEHASH,
                _intent.recipientAmount,
                _intent.deadline,
                _intent.recipient,
                _intent.recipientCurrency,
                _intent.refundDestination,
                _intent.feeAmount,
                _intent.id,
                _intent.operator,
                sender,
                address(this),
                keccak256(_intent.prefix)
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);

        bytes32 signedMessageHash;
        if (_intent.prefix.length == 0) {
            signedMessageHash = digest;
        } else {
            signedMessageHash = keccak256(abi.encodePacked(_intent.prefix, digest));
        }

        address signer = ECDSA.recover(signedMessageHash, _intent.signature);

        if (signer != _intent.operator) {
            revert InvalidSignature();
        }
        if (_intent.deadline < block.timestamp) {
            revert ExpiredIntent();
        }
        if (_intent.recipient == address(0)) {
            revert NullRecipient();
        }
        if (processedTransferIntents[_intent.operator][_intent.id]) {
            revert AlreadyProcessed();
        }
        _;
    }

    /**
     * @dev Checks if the operator specified in the intent is registered.
     * @param _intent The TransferIntent data structure.
     */
    modifier operatorIsRegistered(TransferIntent calldata _intent) {
        if (feeDestinations[_intent.operator] == address(0)) {
            revert OperatorNotRegistered();
        }
        _;
    }

    /**
     * @dev Ensures the exact amount of native currency required by the intent is sent.
     * @param _intent The TransferIntent data structure.
     */
    modifier exactValueSent(TransferIntent calldata _intent) {
        uint256 neededAmount = _intent.recipientAmount + _intent.feeAmount;
        if (msg.value != neededAmount) {
            revert InvalidNativeAmount(int256(msg.value) - int256(neededAmount));
        }
        _;
    }

    // --- Receive Function ---

    /**
     * @dev Allows the contract to receive native currency, primarily for unwrapping WETH during swaps or transfers.
     * @notice Only accepts payments from the wrapped native token contract or the Uniswap router (which might unwrap).
     */
    receive() external payable {
        require(
            msg.sender == address(wrapped) || msg.sender == address(uniswap), "LambdaPay: ONLY_WETH_OR_UNISWAP_PAYABLE"
        );
    }

    // --- External Transfer Functions ---

    /**
     * @inheritdoc ILambdaPay
     * @dev Transfers native currency (e.g., ETH) from the sender to the recipient and fee destination.
     */
    function transferNative(TransferIntent calldata _intent)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        validIntent(_intent, _msgSender())
        operatorIsRegistered(_intent)
        exactValueSent(_intent)
    {
        if (_intent.recipientCurrency != NATIVE_CURRENCY) {
            revert IncorrectCurrency(NATIVE_CURRENCY);
        }

        if (msg.value > 0) {
            transferFundsToDestinations(_intent);
        }

        succeedPayment(_intent, msg.value, NATIVE_CURRENCY, _msgSender());
    }

    /**
     * @inheritdoc ILambdaPay
     * @dev Transfers ERC20 tokens using Permit2 signature for approval.
     */
    function transferToken(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData
    ) external override nonReentrant whenNotPaused validIntent(_intent, _msgSender()) operatorIsRegistered(_intent) {
        address tokenAddress = _signatureTransferData.permit.permitted.token;
        IERC20 erc20 = IERC20(tokenAddress);
        uint256 neededAmount = _intent.recipientAmount + _intent.feeAmount;

        if (_intent.recipientCurrency == NATIVE_CURRENCY || _intent.recipientCurrency != tokenAddress) {
            revert IncorrectCurrency(tokenAddress);
        }

        if (
            _signatureTransferData.transferDetails.to != address(this)
                || _signatureTransferData.transferDetails.requestedAmount != neededAmount
        ) {
            revert InvalidTransferDetails();
        }

        uint256 payerBalance = erc20.balanceOf(_msgSender());
        if (payerBalance < neededAmount) {
            revert InsufficientBalance(neededAmount - payerBalance);
        }

        if (neededAmount > 0) {
            uint256 balanceBefore = erc20.balanceOf(address(this));

            permit2.permitTransferFrom(
                _signatureTransferData.permit,
                _signatureTransferData.transferDetails,
                _msgSender(),
                _signatureTransferData.signature
            );

            revertIfInexactTransfer(neededAmount, balanceBefore, erc20, address(this));

            transferFundsToDestinations(_intent);
        }

        succeedPayment(_intent, neededAmount, tokenAddress, _msgSender());
    }

    /**
     * @inheritdoc ILambdaPay
     * @dev Transfers ERC20 tokens using standard ERC20 allowance (pre-approved).
     */
    function transferTokenPreApproved(TransferIntent calldata _intent)
        external
        override
        nonReentrant
        whenNotPaused
        validIntent(_intent, _msgSender())
        operatorIsRegistered(_intent)
    {
        address tokenAddress = _intent.recipientCurrency;
        IERC20 erc20 = IERC20(tokenAddress);
        uint256 neededAmount = _intent.recipientAmount + _intent.feeAmount;

        if (tokenAddress == NATIVE_CURRENCY) {
            revert IncorrectCurrency(tokenAddress);
        }

        uint256 payerBalance = erc20.balanceOf(_msgSender());
        if (payerBalance < neededAmount) {
            revert InsufficientBalance(neededAmount - payerBalance);
        }

        uint256 allowance = erc20.allowance(_msgSender(), address(this));
        if (allowance < neededAmount) {
            revert InsufficientAllowance(neededAmount - allowance);
        }

        if (neededAmount > 0) {
            uint256 balanceBefore = erc20.balanceOf(address(this));

            erc20.safeTransferFrom(_msgSender(), address(this), neededAmount);

            revertIfInexactTransfer(neededAmount, balanceBefore, erc20, address(this));

            transferFundsToDestinations(_intent);
        }

        succeedPayment(_intent, neededAmount, tokenAddress, _msgSender());
    }

    /**
     * @inheritdoc ILambdaPay
     * @dev Receives native currency, wraps it into WETH, and transfers WETH.
     */
    function wrapAndTransfer(TransferIntent calldata _intent)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        validIntent(_intent, _msgSender())
        operatorIsRegistered(_intent)
        exactValueSent(_intent)
    {
        if (_intent.recipientCurrency != address(wrapped)) {
            revert IncorrectCurrency(address(wrapped));
        }

        if (msg.value > 0) {
            wrapped.deposit{value: msg.value}();

            transferFundsToDestinations(_intent);
        }

        succeedPayment(_intent, msg.value, NATIVE_CURRENCY, _msgSender());
    }

    /**
     * @inheritdoc ILambdaPay
     * @dev Receives WETH via Permit2 signature, unwraps it, and transfers native currency.
     */
    function unwrapAndTransfer(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData
    ) external override nonReentrant whenNotPaused validIntent(_intent, _msgSender()) operatorIsRegistered(_intent) {
        address tokenAddress = _signatureTransferData.permit.permitted.token;
        uint256 neededAmount = _intent.recipientAmount + _intent.feeAmount;

        if (_intent.recipientCurrency != NATIVE_CURRENCY || tokenAddress != address(wrapped)) {
            revert IncorrectCurrency(tokenAddress);
        }

        if (
            _signatureTransferData.transferDetails.to != address(this)
                || _signatureTransferData.transferDetails.requestedAmount != neededAmount
        ) {
            revert InvalidTransferDetails();
        }

        uint256 payerBalance = wrapped.balanceOf(_msgSender());
        if (payerBalance < neededAmount) {
            revert InsufficientBalance(neededAmount - payerBalance);
        }

        if (neededAmount > 0) {
            permit2.permitTransferFrom(
                _signatureTransferData.permit,
                _signatureTransferData.transferDetails,
                _msgSender(),
                _signatureTransferData.signature
            );

            unwrapAndTransferFundsToDestinations(_intent);
        }

        succeedPayment(_intent, neededAmount, address(wrapped), _msgSender());
    }

    /**
     * @inheritdoc ILambdaPay
     * @dev Receives WETH via standard allowance, unwraps it, and transfers native currency.
     */
    function unwrapAndTransferPreApproved(TransferIntent calldata _intent)
        external
        override
        nonReentrant
        whenNotPaused
        validIntent(_intent, _msgSender())
        operatorIsRegistered(_intent)
    {
        uint256 neededAmount = _intent.recipientAmount + _intent.feeAmount;

        if (_intent.recipientCurrency != NATIVE_CURRENCY) {
            revert IncorrectCurrency(address(wrapped));
        }

        uint256 payerBalance = wrapped.balanceOf(_msgSender());
        if (payerBalance < neededAmount) {
            revert InsufficientBalance(neededAmount - payerBalance);
        }

        uint256 allowance = wrapped.allowance(_msgSender(), address(this));
        if (allowance < neededAmount) {
            revert InsufficientAllowance(neededAmount - allowance);
        }

        if (neededAmount > 0) {
            wrapped.safeTransferFrom(_msgSender(), address(this), neededAmount);

            unwrapAndTransferFundsToDestinations(_intent);
        }

        succeedPayment(_intent, neededAmount, address(wrapped), _msgSender());
    }

    /*------------------------------------------------------------------*\
    | Swap and Transfer Functions
    \*------------------------------------------------------------------*/

    /**
     * @inheritdoc ILambdaPay
     * @dev Receives native currency, swaps it via Uniswap V3 for the desired token, and transfers the token.
     */
    function swapAndTransferUniswapV3Native(TransferIntent calldata _intent, uint24 poolFeesTier)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        validIntent(_intent, _msgSender())
        operatorIsRegistered(_intent)
    {
        if (_intent.recipientCurrency == NATIVE_CURRENCY || _intent.recipientCurrency == address(wrapped)) {
            revert IncorrectCurrency(NATIVE_CURRENCY);
        }

        uint256 neededAmountOut = _intent.recipientAmount + _intent.feeAmount;
        uint256 amountSwapped = 0;

        if (neededAmountOut > 0) {
            if (msg.value == 0) {
                revert InvalidNativeAmount(-int256(neededAmountOut));
            }

            amountSwapped = swapTokens(_intent, address(wrapped), msg.value, poolFeesTier);
        }

        succeedPayment(_intent, amountSwapped, NATIVE_CURRENCY, _msgSender());
    }

    /**
     * @inheritdoc ILambdaPay
     * @dev Receives tokens via Permit2, swaps via Uniswap V3, and transfers the output token/native currency.
     */
    function swapAndTransferUniswapV3Token(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData,
        uint24 poolFeesTier
    ) external override nonReentrant whenNotPaused validIntent(_intent, _msgSender()) operatorIsRegistered(_intent) {
        address tokenIn = _signatureTransferData.permit.permitted.token;
        IERC20 erc20In = IERC20(tokenIn);
        uint256 neededAmountOut = _intent.recipientAmount + _intent.feeAmount;
        uint256 maxWillingToPay = _signatureTransferData.transferDetails.requestedAmount;

        if (tokenIn == _intent.recipientCurrency) {
            revert IncorrectCurrency(tokenIn);
        }

        if (_signatureTransferData.transferDetails.to != address(this)) {
            revert InvalidTransferDetails();
        }

        uint256 amountSwapped = 0;

        if (neededAmountOut > 0) {
            if (maxWillingToPay == 0) {
                revert InvalidTransferDetails();
            }

            uint256 balanceBefore = erc20In.balanceOf(address(this));

            permit2.permitTransferFrom(
                _signatureTransferData.permit,
                _signatureTransferData.transferDetails,
                _msgSender(),
                _signatureTransferData.signature
            );

            revertIfInexactTransfer(maxWillingToPay, balanceBefore, erc20In, address(this));

            amountSwapped = swapTokens(_intent, tokenIn, maxWillingToPay, poolFeesTier);
        }

        succeedPayment(_intent, amountSwapped, tokenIn, _msgSender());
    }

    /**
     * @inheritdoc ILambdaPay
     * @dev Receives tokens via standard allowance, swaps via Uniswap V3, and transfers the output token/native currency.
     */
    function swapAndTransferUniswapV3TokenPreApproved(
        TransferIntent calldata _intent,
        address _tokenIn,
        uint256 maxWillingToPay,
        uint24 poolFeesTier
    ) external override nonReentrant whenNotPaused validIntent(_intent, _msgSender()) operatorIsRegistered(_intent) {
        IERC20 tokenIn = IERC20(_tokenIn);
        uint256 neededAmountOut = _intent.recipientAmount + _intent.feeAmount;

        if (_tokenIn == _intent.recipientCurrency) {
            revert IncorrectCurrency(_tokenIn);
        }

        uint256 payerBalance = tokenIn.balanceOf(_msgSender());
        if (payerBalance < maxWillingToPay) {
            revert InsufficientBalance(maxWillingToPay - payerBalance);
        }
        uint256 allowance = tokenIn.allowance(_msgSender(), address(this));
        if (allowance < maxWillingToPay) {
            revert InsufficientAllowance(maxWillingToPay - allowance);
        }

        uint256 amountSwapped = 0;

        if (neededAmountOut > 0) {
            if (maxWillingToPay == 0) {
                revert InsufficientAllowance(0);
            }

            uint256 balanceBefore = tokenIn.balanceOf(address(this));

            tokenIn.safeTransferFrom(_msgSender(), address(this), maxWillingToPay);

            revertIfInexactTransfer(maxWillingToPay, balanceBefore, tokenIn, address(this));

            amountSwapped = swapTokens(_intent, _tokenIn, maxWillingToPay, poolFeesTier);
        }

        succeedPayment(_intent, amountSwapped, _tokenIn, _msgSender());
    }

    /**
     * @inheritdoc ILambdaPay
     * @dev Transfers tokens using EIP-2612 permit for gasless approval from the owner. Transaction fee paid by msg.sender.
     */
    function subsidizedTransferToken(
        TransferIntent calldata _intent,
        EIP2612SignatureTransferData calldata _signatureTransferData
    )
        external
        override
        nonReentrant
        whenNotPaused
        validIntent(_intent, _signatureTransferData.owner)
        operatorIsRegistered(_intent)
    {
        address tokenAddress = _intent.recipientCurrency;
        IERC20 erc20 = IERC20(tokenAddress);
        IERC7597 permitToken = IERC7597(tokenAddress);
        uint256 neededAmount = _intent.recipientAmount + _intent.feeAmount;
        address owner = _signatureTransferData.owner;

        if (tokenAddress == NATIVE_CURRENCY) {
            revert IncorrectCurrency(tokenAddress);
        }

        uint256 ownerBalance = erc20.balanceOf(owner);
        if (ownerBalance < neededAmount) {
            revert InsufficientBalance(neededAmount - ownerBalance);
        }

        uint256 nonceBefore = permitToken.nonces(owner);

        try permitToken.permit(owner, address(this), neededAmount, _intent.deadline, _signatureTransferData.signature) {
            if (permitToken.nonces(owner) != nonceBefore + 1) {
                revert PermitCallFailed();
            }
        } catch {
            revert PermitCallFailed();
        }

        uint256 allowance = erc20.allowance(owner, address(this));
        if (allowance < neededAmount) {
            revert InsufficientAllowance(neededAmount - allowance);
        }

        if (neededAmount > 0) {
            uint256 balanceBefore = erc20.balanceOf(address(this));

            erc20.safeTransferFrom(owner, address(this), neededAmount);

            revertIfInexactTransfer(neededAmount, balanceBefore, erc20, address(this));

            transferFundsToDestinations(_intent);
        }

        succeedPayment(_intent, neededAmount, tokenAddress, owner);
    }

    // --- Owner / Admin Functions ---

    /**
     * @notice Registers the caller (`msg.sender`) as an operator with a specific fee destination.
     * @dev Emits an {OperatorRegistered} event.
     * @param _feeDestination The address where operator fees should be sent. Cannot be address(0).
     */
    function registerOperatorWithFeeDestination(address _feeDestination) external {
        require(_feeDestination != address(0), "LambdaPay: ZERO_FEE_DESTINATION");
        feeDestinations[_msgSender()] = _feeDestination;
        emit OperatorRegistered(_msgSender(), _feeDestination);
    }

    /**
     * @notice Registers the caller (`msg.sender`) as an operator, using their own address as the fee destination.
     * @dev Emits an {OperatorRegistered} event.
     */
    function registerOperator() external {
        address operator = _msgSender();
        feeDestinations[operator] = operator;
        emit OperatorRegistered(operator, operator);
    }

    /**
     * @notice Unregisters the caller (`msg.sender`) as an operator, removing their fee destination.
     * @dev Emits an {OperatorUnregistered} event.
     */
    function unregisterOperator() external {
        address operator = _msgSender();
        delete feeDestinations[operator];
        emit OperatorUnregistered(operator);
    }

    /**
     * @notice Pauses the contract, preventing new transfers. Called by the owner.
     * @dev Emits a {Paused} event. See {Pausable}.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, resuming transfer functionality. Called by the owner.
     * @dev Emits an {Unpaused} event. See {Pausable}.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // --- Internal Functions ---

    /**
     * @dev Performs the swap using Uniswap Universal Router. Handles different input/output types.
     * @notice Assumes input funds (tokenIn or wrapped ETH from msg.value) are already held by this contract.
     * @param _intent The transfer intent containing output details.
     * @param _tokenIn Address of the token being swapped *from* (could be WETH if input was native).
     * @param _maxAmountWillingToPay The maximum amount of `_tokenIn` to spend (or native `msg.value`).
     * @param _poolFeesTier The Uniswap V3 pool fee tier.
     * @return amountConsumed The actual amount of `_tokenIn` (or native) consumed by the swap and transfers.
     * @dev Uses V3_SWAP_EXACT_OUT to guarantee the recipient/fee destination receive the exact required amount.
     *      The transaction will revert if `_maxAmountWillingToPay` is insufficient due to price slippage.
     *      Refunds unused input (_tokenIn or native) back to the original payer (`_msgSender()`).
     */
    function swapTokens(
        TransferIntent calldata _intent,
        address _tokenIn,
        uint256 _maxAmountWillingToPay,
        uint24 _poolFeesTier
    ) internal returns (uint256 amountConsumed) {
        address tokenOut = (_intent.recipientCurrency == NATIVE_CURRENCY) ? address(wrapped) : _intent.recipientCurrency;

        uint256 neededAmountOut = _intent.recipientAmount + _intent.feeAmount;

        bytes memory commands;
        bytes[] memory inputs;
        bytes memory swapPath = abi.encodePacked(tokenOut, _poolFeesTier, _tokenIn);
        bytes memory swapParams = abi.encode(address(this), neededAmountOut, _maxAmountWillingToPay, swapPath, false);

        bytes memory transferRecipientParams =
            abi.encode(_intent.recipientCurrency, _intent.recipient, _intent.recipientAmount);
        bytes memory transferFeeParams =
            abi.encode(_intent.recipientCurrency, feeDestinations[_intent.operator], _intent.feeAmount);

        uint256 payerBalanceBefore;
        uint256 routerBalanceBefore;
        uint256 feeRecipientBalanceBefore;
        uint256 primaryRecipientBalanceBefore;

        if (msg.value > 0) {
            payerBalanceBefore = _msgSender().balance + msg.value;
            routerBalanceBefore = address(uniswap).balance + wrapped.balanceOf(address(uniswap));

            if (_intent.recipientCurrency != NATIVE_CURRENCY) {
                feeRecipientBalanceBefore = IERC20(tokenOut).balanceOf(feeDestinations[_intent.operator]);
                primaryRecipientBalanceBefore = IERC20(tokenOut).balanceOf(_intent.recipient);
            }

            commands = abi.encodePacked(
                bytes1(uint8(Commands.WRAP_ETH)),
                bytes1(uint8(Commands.V3_SWAP_EXACT_OUT)),
                bytes1(uint8(Commands.TRANSFER)),
                bytes1(uint8(Commands.TRANSFER)),
                bytes1(uint8(Commands.UNWRAP_WETH)),
                bytes1(uint8(Commands.SWEEP))
            );
            inputs = new bytes[](6);
            inputs[0] = abi.encode(address(this), msg.value);
            inputs[1] = swapParams;
            inputs[2] = transferFeeParams;
            inputs[3] = transferRecipientParams;
            inputs[4] = abi.encode(address(uniswap), uint256(0));
            inputs[5] = abi.encode(Constants.ETH, _msgSender(), uint256(0));
        } else {
            payerBalanceBefore = IERC20(_tokenIn).balanceOf(_msgSender()) + _maxAmountWillingToPay;
            routerBalanceBefore = IERC20(_tokenIn).balanceOf(address(uniswap));

            IERC20(_tokenIn).safeTransfer(address(uniswap), _maxAmountWillingToPay);

            if (_intent.recipientCurrency == NATIVE_CURRENCY) {
                commands = abi.encodePacked(
                    bytes1(uint8(Commands.V3_SWAP_EXACT_OUT)),
                    bytes1(uint8(Commands.UNWRAP_WETH)),
                    bytes1(uint8(Commands.TRANSFER)),
                    bytes1(uint8(Commands.TRANSFER)),
                    bytes1(uint8(Commands.SWEEP))
                );
                inputs = new bytes[](5);
                inputs[0] = swapParams;
                inputs[1] = abi.encode(address(this), neededAmountOut);
                inputs[2] = transferFeeParams;
                inputs[3] = transferRecipientParams;
                inputs[4] = abi.encode(_tokenIn, _msgSender(), uint256(0));
            } else {
                feeRecipientBalanceBefore = IERC20(tokenOut).balanceOf(feeDestinations[_intent.operator]);
                primaryRecipientBalanceBefore = IERC20(tokenOut).balanceOf(_intent.recipient);

                commands = abi.encodePacked(
                    bytes1(uint8(Commands.V3_SWAP_EXACT_OUT)),
                    bytes1(uint8(Commands.TRANSFER)),
                    bytes1(uint8(Commands.TRANSFER)),
                    bytes1(uint8(Commands.SWEEP))
                );
                inputs = new bytes[](4);
                inputs[0] = swapParams;
                inputs[1] = transferFeeParams;
                inputs[2] = transferRecipientParams;
                inputs[3] = abi.encode(_tokenIn, _msgSender(), uint256(0));
            }
        }

        try uniswap.execute{value: msg.value}(commands, inputs, _intent.deadline) {
            if (_intent.recipientCurrency != NATIVE_CURRENCY) {
                revertIfInexactTransfer(
                    _intent.feeAmount, feeRecipientBalanceBefore, IERC20(tokenOut), feeDestinations[_intent.operator]
                );
                revertIfInexactTransfer(
                    _intent.recipientAmount, primaryRecipientBalanceBefore, IERC20(tokenOut), _intent.recipient
                );
            }

            uint256 payerBalanceAfter;
            uint256 routerBalanceAfter;
            if (msg.value > 0) {
                payerBalanceAfter = _msgSender().balance;
                routerBalanceAfter = address(uniswap).balance + wrapped.balanceOf(address(uniswap));
            } else {
                payerBalanceAfter = IERC20(_tokenIn).balanceOf(_msgSender());
                routerBalanceAfter = IERC20(_tokenIn).balanceOf(address(uniswap));
            }
            amountConsumed = (payerBalanceBefore + routerBalanceBefore) - (payerBalanceAfter + routerBalanceAfter);
        } catch Error(string memory reason) {
            revert SwapFailedString(reason);
        } catch (bytes memory reason) {
            bytes32 reasonHash = keccak256(reason);
            if (reasonHash == V3_INVALID_SWAP) {
                revert SwapFailedString("V3InvalidSwap");
            }
            if (reasonHash == V3_TOO_LITTLE_RECEIVED) {
                revert SwapFailedString("V3TooLittleReceived");
            }
            if (reasonHash == V3_TOO_MUCH_REQUESTED) {
                revert SwapFailedString("V3TooMuchRequested");
            }
            if (reasonHash == V3_INVALID_AMOUNT_OUT) {
                revert SwapFailedString("V3InvalidAmountOut");
            }
            if (reasonHash == V3_INVALID_CALLER) {
                revert SwapFailedString("V3InvalidCaller");
            }
            revert SwapFailedBytes(reason);
        }

        return amountConsumed;
    }

    /**
     * @dev Internal function to transfer funds (native or token) to the recipient and fee destination.
     * @notice Assumes the required funds are held by this contract.
     * @param _intent The transfer intent containing destination and amount details.
     */
    function transferFundsToDestinations(TransferIntent calldata _intent) internal {
        address feeDestination = feeDestinations[_intent.operator];

        if (_intent.recipientCurrency == NATIVE_CURRENCY) {
            if (_intent.recipientAmount > 0) {
                sendNative(_intent.recipient, _intent.recipientAmount, false);
            }
            if (_intent.feeAmount > 0) {
                sendNative(feeDestination, _intent.feeAmount, false);
            }
        } else {
            IERC20 requestedCurrency = IERC20(_intent.recipientCurrency);
            if (_intent.recipientAmount > 0) {
                requestedCurrency.safeTransfer(_intent.recipient, _intent.recipientAmount);
            }
            if (_intent.feeAmount > 0) {
                requestedCurrency.safeTransfer(feeDestination, _intent.feeAmount);
            }
        }
    }

    /**
     * @dev Internal function to unwrap WETH held by this contract and then transfer native currency.
     * @notice Assumes the required WETH amount is held by this contract.
     * @param _intent The transfer intent containing destination and amount details (expecting native output).
     */
    function unwrapAndTransferFundsToDestinations(TransferIntent calldata _intent) internal {
        uint256 amountToWithdraw = _intent.recipientAmount + _intent.feeAmount;
        if (amountToWithdraw > 0) {
            require(_intent.recipientCurrency == NATIVE_CURRENCY, "LambdaPay: UNWRAP_REQUIRES_NATIVE_OUT");
            wrapped.withdraw(amountToWithdraw);
        }
        transferFundsToDestinations(_intent);
    }

    /**
     * @dev Marks an intent as processed and emits the Transferred event.
     * @param _intent The transfer intent that succeeded.
     * @param _spentAmount The amount of input currency spent by the payer.
     * @param _spentCurrency The address of the input currency spent by the payer.
     * @param _sender The address initiating the transfer (payer or subsidized owner).
     */
    function succeedPayment(
        TransferIntent calldata _intent,
        uint256 _spentAmount,
        address _spentCurrency,
        address _sender
    ) internal {
        processedTransferIntents[_intent.operator][_intent.id] = true;
        emit Transferred(
            _intent.operator,
            _intent.id,
            _intent.recipient,
            _sender,
            _spentAmount,
            _spentCurrency,
            _intent.recipientAmount,
            _intent.recipientCurrency
        );
    }

    /**
     * @dev Safely sends native currency (ETH).
     * @param destination The recipient address.
     * @param amount The amount to send.
     * @param isRefund Flag used in revert message to differentiate payment vs refund failures.
     */
    function sendNative(address destination, uint256 amount, bool isRefund) internal {
        (bool success, bytes memory data) = payable(destination).call{value: amount}("");
        if (!success) {
            revert NativeTransferFailed(destination, amount, isRefund, data);
        }
    }

    /**
     * @dev Reverts if the balance change of a token for a target address does not match the expected difference.
     * @notice Used to detect fee-on-transfer tokens during deposits or distributions.
     * @param expectedDiff The expected change in balance.
     * @param balanceBefore The target's balance before the transfer.
     * @param token The ERC20 token contract.
     * @param target The address whose balance is checked.
     */
    function revertIfInexactTransfer(uint256 expectedDiff, uint256 balanceBefore, IERC20 token, address target)
        internal
        view
    {
        uint256 balanceAfter = token.balanceOf(target);
        if (balanceAfter < balanceBefore || balanceAfter - balanceBefore != expectedDiff) {
            revert InexactTransfer(address(token), target, expectedDiff, balanceAfter - balanceBefore);
        }
    }
}

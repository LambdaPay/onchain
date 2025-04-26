// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IWrapped} from "../../contracts/interfaces/IWrapped.sol";
import {MockERC20} from "./MockERC20.sol";
import {LambdaPay} from "../../contracts/LambdaPay.sol";
import {IWETH9} from "../../lib/universal-router/contracts/interfaces/external/IWETH9.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUniversalRouter
 * @dev A simplified mock for testing that implements bare minimum Uniswap
 * Universal Router functionality. Not a fully compliant implementation.
 */
contract MockUniversalRouter {
    IWrapped public immutable wrappedNative;
    mapping(address => mapping(address => uint256)) public exchangeRates;

    // Track if tokens were received to ensure mock behaves correctly
    bool public receivedTokens;

    // Flag to control whether the router automatically sends tokens to recipients
    bool public autoSend;

    // Uniswap V3 command constants
    uint8 constant UNWRAP_WETH = 0x02;
    uint8 constant TRANSFER = 0x07;
    uint8 constant SWEEP = 0x08;
    uint8 constant V3_SWAP_EXACT_OUT = 0x0a;

    constructor(IWrapped _wrappedNative) {
        wrappedNative = _wrappedNative;
    }

    /**
     * @dev Set the exchange rate between two tokens (1 tokenIn = rate * tokenOut)
     */
    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external {
        exchangeRates[tokenIn][tokenOut] = rate;
        // If rate is 0, default to 1:1
        if (rate == 0) {
            exchangeRates[tokenIn][tokenOut] = 1e18;
        }
    }

    /**
     * @dev Set whether the router should automatically send tokens to recipients
     */
    function setAutoSend(bool _autoSend) external {
        autoSend = _autoSend;
    }

    /**
     * @dev Simplified execution function that simulates swaps
     */
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable {
        require(deadline >= block.timestamp, "MockUniversalRouter: EXPIRED");

        // Track received tokens
        receivedTokens = true;

        // For the LambdaPay swap test, we need to handle the exact scenario
        // where we swap tokenIn for tokenOut and then transfer to fee destination and recipient

        if (
            commands.length >= 4 && uint8(commands[0]) == V3_SWAP_EXACT_OUT && uint8(commands[1]) == TRANSFER
                && uint8(commands[2]) == TRANSFER && autoSend
        ) {
            // Get token details from TRANSFER commands
            address feeTokenOut;
            address feeDestination;
            uint256 feeAmount;
            (feeTokenOut, feeDestination, feeAmount) = abi.decode(inputs[1], (address, address, uint256));

            address recipientTokenOut;
            address recipient;
            uint256 recipientAmount;
            (recipientTokenOut, recipient, recipientAmount) = abi.decode(inputs[2], (address, address, uint256));

            // Transfer tokens directly to both destinations
            if (feeAmount > 0) {
                // Direct transfer from our balance
                IERC20(feeTokenOut).transfer(feeDestination, feeAmount);
            }

            if (recipientAmount > 0) {
                // Direct transfer from our balance
                IERC20(recipientTokenOut).transfer(recipient, recipientAmount);
            }

            // Get sweep details to return excess tokens
            if (commands.length > 3 && uint8(commands[3]) == SWEEP) {
                address tokenIn;
                address returnTo;
                (tokenIn, returnTo,) = abi.decode(inputs[3], (address, address, uint256));

                // Return any unused input tokens
                // For our test, assume we used exactly the input tokens needed
                // This is a simplification for testing purposes
                uint256 totalOut = feeAmount + recipientAmount;
                uint256 rate = exchangeRates[tokenIn][feeTokenOut];
                uint256 inputUsed = (totalOut * 1e18) / rate;

                // Get current balance of tokenIn
                uint256 balance = IERC20(tokenIn).balanceOf(address(this));
                // Keep only the amount we didn't use for the swap
                if (balance > inputUsed) {
                    IERC20(tokenIn).transfer(returnTo, balance - inputUsed);
                }
            }

            return;
        }

        // Process commands based on our simplified mock
        for (uint256 i = 0; i < commands.length; i++) {
            uint8 command = uint8(commands[i]);

            // Handle WRAP_ETH command (command 0x01)
            if (command == 0x01) {
                // Wrap native ETH to wrapped token
                if (msg.value > 0) {
                    wrappedNative.deposit{value: msg.value}();
                }
            }
            // Handle V3_SWAP_EXACT_OUT command (command 0x0a)
            else if (command == V3_SWAP_EXACT_OUT) {
                // Parse basic swap parameters (simplified)
                // In real Universal Router, inputs would contain complex swap params
                address recipient = address(this);
                address tokenOut;
                uint256 amountOut;

                // Extract these from inputs for our mock
                (recipient, amountOut,,,) = abi.decode(inputs[i], (address, uint256, uint256, bytes, bool));

                // Handle different types of swaps
                // For our mock, we'll just transfer tokens as if swap happened successfully
                if (i + 1 < commands.length && uint8(commands[i + 1]) == UNWRAP_WETH) {
                    // Next command is UNWRAP_WETH, so tokenOut is wrapped native
                    tokenOut = address(wrappedNative);
                    IERC20(tokenOut).transfer(recipient, amountOut);
                } else if (i + 1 < inputs.length) {
                    // Extract tokenOut from next input (transfer command)
                    (tokenOut,,) = abi.decode(inputs[i + 1], (address, address, uint256));

                    // Ensure the token exists and is funded for test
                    uint256 balance = IERC20(tokenOut).balanceOf(address(this));
                    if (balance < amountOut) {
                        // This is for testing only - in real router it would revert
                        // Mint tokens for testing to simulate the swap
                        MockERC20(tokenOut).mint(address(this), amountOut);
                    }

                    IERC20(tokenOut).transfer(recipient, amountOut);
                }
            }
            // Handle TRANSFER command (command 0x07)
            else if (command == TRANSFER) {
                address token;
                address to;
                uint256 amount;

                (token, to, amount) = abi.decode(inputs[i], (address, address, uint256));

                if (token == address(0)) {
                    // Handle native ETH transfer
                    (bool sent,) = to.call{value: amount}("");
                    require(sent, "MockUniversalRouter: ETH transfer failed");
                } else {
                    // Handle ERC20 transfer - ensure we have enough tokens
                    uint256 balance = IERC20(token).balanceOf(address(this));
                    if (balance < amount) {
                        // Mock the token creation if we don't have enough
                        if (token == address(wrappedNative)) {
                            wrappedNative.deposit{value: amount}();
                        } else {
                            // This is a test, so just mint tokens if missing
                            // In a real environment, this would fail
                            require(amount > 0, "Cannot transfer 0 tokens");
                            MockERC20(token).mint(address(this), amount);
                        }
                    }

                    // Actually transfer the tokens
                    bool success = IERC20(token).transfer(to, amount);
                    require(success, "MockUniversalRouter: ERC20 transfer failed");
                }
            }
            // Handle UNWRAP_WETH command (command 0x02)
            else if (command == UNWRAP_WETH) {
                address recipient;
                uint256 amountMinimum;

                (recipient, amountMinimum) = abi.decode(inputs[i], (address, uint256));

                uint256 balance = wrappedNative.balanceOf(address(this));
                if (balance >= amountMinimum) {
                    wrappedNative.withdraw(balance);
                    (bool sent,) = recipient.call{value: balance}("");
                    require(sent, "MockUniversalRouter: ETH transfer failed");
                }
            }
            // Handle SWEEP command (command 0x08)
            else if (command == SWEEP) {
                address token;
                address recipient;
                uint256 amountMinimum;

                (token, recipient, amountMinimum) = abi.decode(inputs[i], (address, address, uint256));

                if (token == address(0)) {
                    // Handle native ETH sweep
                    uint256 balance = address(this).balance;
                    if (balance > 0) {
                        (bool sent,) = recipient.call{value: balance}("");
                        require(sent, "MockUniversalRouter: ETH transfer failed");
                    }
                } else {
                    // Handle ERC20 sweep
                    uint256 balance = IERC20(token).balanceOf(address(this));
                    if (balance > amountMinimum) {
                        IERC20(token).transfer(recipient, balance);
                    }
                }
            }
        }
    }

    /**
     * @dev Handle rewards collection (empty implementation)
     */
    function collectRewards(bytes calldata) external {
        // No implementation needed for mock
    }

    /**
     * @dev Simplified method to support ERC721 token receives
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev Simplified method to support ERC1155 token receives
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Simplified method to support ERC1155 batch receives
     */
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Simplified method to support interface detection
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    // Allow the contract to receive ETH
    receive() external payable {}
}

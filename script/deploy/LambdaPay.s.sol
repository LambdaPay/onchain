// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LambdaPay} from "@lambdapay/onchain/contracts/LambdaPay.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Permit2} from "@lambdapay/onchain/contracts/permit2/Permit2.sol";
import {IWrapped} from "@lambdapay/onchain/contracts/interfaces/IWrapped.sol";

/**
 * @title LambdaPay Deployment Script
 * @notice Production script for deploying the LambdaPay contract to any EVM chain
 * @dev Loads configuration from environment variables to support cross-chain deployments
 */
contract LambdaPayDeploy is Script {
    // Network-specific addresses
    address public uniswapUniversalRouter;
    address public permit2Address;
    address public wrappedNative;

    // Initial operator and fee destination
    address public initialOperator;
    address public initialFeeDestination;

    // EIP-712 domain parameters
    string constant EIP712_NAME = "LambdaPay";
    string constant EIP712_VERSION = "1";

    /**
     * @notice Set up the deployment configuration
     * @dev Loads addresses from environment variables with fallbacks to mainnet values
     */
    function setUp() public {
        // Load network-specific addresses from environment
        uniswapUniversalRouter =
            vm.envOr("UNISWAP_UNIVERSAL_ROUTER", address(0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD));
        permit2Address = vm.envOr("PERMIT2", address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
        wrappedNative = vm.envOr("WRAPPED_NATIVE", address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

        // Load operator and fee destination
        initialOperator = vm.envOr("INITIAL_OPERATOR", address(0x1234567890123456789012345678901234567890));
        initialFeeDestination = vm.envOr("FEE_DESTINATION", address(0x1234567890123456789012345678901234567890));

        // Log configuration
        console.log("Deploying LambdaPay with configuration:");
        console.log("Universal Router:", uniswapUniversalRouter);
        console.log("Permit2:", permit2Address);
        console.log("Wrapped Native:", wrappedNative);
        console.log("Initial Operator:", initialOperator);
        console.log("Fee Destination:", initialFeeDestination);
    }

    /**
     * @notice Deploy the LambdaPay contract
     */
    function run() public {
        vm.startBroadcast();

        // Deploy LambdaPay contract
        LambdaPay lambdaPay = new LambdaPay(
            IUniversalRouter(uniswapUniversalRouter),
            Permit2(permit2Address),
            initialOperator,
            initialFeeDestination,
            IWrapped(wrappedNative),
            EIP712_NAME,
            EIP712_VERSION
        );

        console.log("LambdaPay deployed at:", address(lambdaPay));

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LambdaPay} from "@lambdapay/onchain/contracts/LambdaPay.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Permit2} from "@lambdapay/onchain/contracts/permit2/Permit2.sol";
import {IWrapped} from "@lambdapay/onchain/contracts/interfaces/IWrapped.sol";
import {MockUniversalRouter, MockPermit2, MockWrapped} from "../mocks/Mocks.sol";

/**
 * @title TestLambdaPay
 * @notice Test script for deploying LambdaPay with mock dependencies
 * @dev Used for local testing on Anvil
 */
contract TestLambdaPay is Script {
    // Test parameters
    address public uniswapUniversalRouter;
    address public permit2Address;
    address public wrappedNative;
    address public initialOperator;
    address public initialFeeDestination;

    // EIP-712 domain parameters
    string constant EIP712_NAME = "LambdaPay";
    string constant EIP712_VERSION = "1";

    /**
     * @notice Set up test parameters
     */
    function setUp() public {
        // Use default anvil addresses for testing
        initialOperator = vm.addr(1); // First address in anvil
        initialFeeDestination = vm.addr(2); // Second address in anvil

        console.log("Test setup:");
        console.log("Initial Operator:", initialOperator);
        console.log("Fee Destination:", initialFeeDestination);
    }

    /**
     * @notice Deploy LambdaPay with mock dependencies for testing
     */
    function run() public {
        vm.startBroadcast();

        // Deploy mock dependencies
        MockUniversalRouter mockRouter = new MockUniversalRouter();
        MockPermit2 mockPermit2 = new MockPermit2();
        MockWrapped mockWrapped = new MockWrapped();

        uniswapUniversalRouter = address(mockRouter);
        permit2Address = address(mockPermit2);
        wrappedNative = address(mockWrapped);

        console.log("Deployed mock dependencies:");
        console.log("Mock Universal Router:", uniswapUniversalRouter);
        console.log("Mock Permit2:", permit2Address);
        console.log("Mock Wrapped Native:", wrappedNative);

        // Deploy LambdaPay using standard new operator
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

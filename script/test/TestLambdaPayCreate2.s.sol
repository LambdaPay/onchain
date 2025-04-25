// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LambdaPay} from "@lambdapay/onchain/contracts/LambdaPay.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Permit2} from "@lambdapay/onchain/contracts/permit2/Permit2.sol";
import {IWrapped} from "@lambdapay/onchain/contracts/interfaces/IWrapped.sol";
import {MockUniversalRouter, MockPermit2, MockWrapped, Create2Factory} from "../mocks/Mocks.sol";

/**
 * @title TestLambdaPayCreate2
 * @notice Test script for deploying LambdaPay with CREATE2 for deterministic addresses
 * @dev Uses a custom CREATE2Factory that's deployed as part of the test
 */
contract TestLambdaPayCreate2 is Script {
    // Deployed mock contract addresses
    address public uniswapUniversalRouter;
    address public permit2Address;
    address public wrappedNative;

    // Initial operator and fee destination
    address public initialOperator;
    address public initialFeeDestination;

    // CREATE2 factory
    Create2Factory public create2Factory;

    // EIP-712 domain parameters
    string constant EIP712_NAME = "LambdaPay";
    string constant EIP712_VERSION = "1";

    // CREATE2 salt - must be the same across all chains
    bytes32 constant SALT = bytes32(uint256(0x123456789));

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
     * @notice Deploy LambdaPay using CREATE2 for testing
     */
    function run() public {
        vm.startBroadcast();

        // 1. Deploy mock dependencies first
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

        // 2. Deploy our own CREATE2 factory first
        create2Factory = new Create2Factory();
        console.log("CREATE2 Factory deployed at:", address(create2Factory));

        // 3. Calculate the bytecode for LambdaPay deployment
        bytes memory creationCode = abi.encodePacked(
            type(LambdaPay).creationCode,
            abi.encode(
                IUniversalRouter(uniswapUniversalRouter),
                Permit2(permit2Address),
                initialOperator,
                initialFeeDestination,
                IWrapped(wrappedNative),
                EIP712_NAME,
                EIP712_VERSION
            )
        );

        // Calculate the expected contract address
        address predictedAddress = create2Factory.computeAddress(SALT, keccak256(creationCode));
        console.log("Predicted LambdaPay address:", predictedAddress);

        // Deploy using our CREATE2 factory
        address deployedAddress = create2Factory.deploy(SALT, creationCode);
        console.log("LambdaPay deployed at:", deployedAddress);

        // Verify addresses match
        require(predictedAddress == deployedAddress, "Deployment address mismatch");

        vm.stopBroadcast();
    }
}

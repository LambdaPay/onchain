// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LambdaPay} from "@lambdapay/onchain/contracts/LambdaPay.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Permit2} from "@lambdapay/onchain/contracts/permit2/Permit2.sol";
import {IWrapped} from "@lambdapay/onchain/contracts/interfaces/IWrapped.sol";
import {Create2Factory} from "../mocks/Mocks.sol";

/**
 * @title LambdaPay CREATE2 Deployment Script
 * @notice Production script for deploying the LambdaPay contract to any EVM chain with deterministic address
 * @dev Uses CREATE2 deployment to ensure the same contract address across all chains
 */
contract LambdaPayCreate2Deploy is Script {
    // Network-specific addresses
    address public uniswapUniversalRouter;
    address public permit2Address;
    address public wrappedNative;

    // Initial operator and fee destination
    address public initialOperator;
    address public initialFeeDestination;

    // CREATE2 factory address - universal deployer contract available on most chains
    // https://github.com/Arachnid/deterministic-deployment-proxy
    address constant UNIVERSAL_CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // EIP-712 domain parameters
    string constant EIP712_NAME = "LambdaPay";
    string constant EIP712_VERSION = "1";

    // CREATE2 salt - must be the same across all chains
    bytes32 constant SALT = bytes32(uint256(0x123456789));

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
        console.log("Deploying LambdaPay with CREATE2 configuration:");
        console.log("Universal Router:", uniswapUniversalRouter);
        console.log("Permit2:", permit2Address);
        console.log("Wrapped Native:", wrappedNative);
        console.log("Initial Operator:", initialOperator);
        console.log("Fee Destination:", initialFeeDestination);
        console.log("CREATE2 Salt:", uint256(SALT));
    }

    /**
     * @notice Deploy the LambdaPay contract using CREATE2
     */
    function run() public {
        vm.startBroadcast();

        // Prepare the creation bytecode with constructor parameters
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
        bytes32 creationCodeHash = keccak256(creationCode);
        address predictedAddress = calculateCreate2Address(SALT, creationCodeHash);
        console.log("Predicted LambdaPay address:", predictedAddress);

        // Check if contract already exists at the predicted address
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(predictedAddress)
        }

        if (codeSize > 0) {
            console.log("LambdaPay already deployed at predicted address");
        } else {
            // Use the factory to deploy with CREATE2
            (bool success,) = UNIVERSAL_CREATE2_FACTORY.call(abi.encodePacked(SALT, creationCode));
            require(success, "CREATE2 deployment failed");

            // Verify deployment
            assembly {
                codeSize := extcodesize(predictedAddress)
            }
            require(codeSize > 0, "Deployment verification failed");
            console.log("LambdaPay deployed at:", predictedAddress);
        }

        vm.stopBroadcast();
    }

    /**
     * @notice Helper function to calculate CREATE2 address without deploying
     * @param salt Salt used in CREATE2 deployment
     * @param bytecodeHash Hash of contract creation bytecode
     */
    function calculateCreate2Address(bytes32 salt, bytes32 bytecodeHash) public pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), UNIVERSAL_CREATE2_FACTORY, salt, bytecodeHash))))
        );
    }

    /**
     * @notice Helper function to get the expected address without deploying
     * @dev Can be called via forge script with --sig "getAddress()"
     */
    function getAddress() external view returns (address) {
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

        return calculateCreate2Address(SALT, keccak256(creationCode));
    }
}

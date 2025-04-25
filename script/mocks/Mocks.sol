// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title MockUniversalRouter
 * @notice Minimal mock of Uniswap Universal Router for testing
 */
contract MockUniversalRouter {
    function execute(
        bytes calldata, // commands
        bytes[] calldata, // inputs
        uint256 // deadline
    ) external payable {}
}

/**
 * @title MockWrapped
 * @notice Minimal mock of wrapped native token (e.g., WETH) for testing
 */
contract MockWrapped {
    function deposit() external payable {}
    function withdraw(uint256) external {}

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }
}

/**
 * @title MockPermit2
 * @notice Minimal mock of Uniswap Permit2 for testing
 */
contract MockPermit2 {
    function permitTransferFrom(
        address, // token
        address, // from
        address, // to
        uint256, // amount
        uint256, // deadline
        bytes calldata // signature
    ) external {}
}

/**
 * @title Create2Factory
 * @notice Utility contract for deterministic deployments using CREATE2
 */
contract Create2Factory {
    event Deployed(address addr, bytes32 salt);

    function computeAddress(bytes32 salt, bytes32 codeHash) public view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))));
    }

    function deploy(bytes32 salt, bytes memory bytecode) public payable returns (address deployedAddress) {
        assembly {
            deployedAddress := create2(callvalue(), add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(deployedAddress != address(0), "Create2: Failed on deploy");
        emit Deployed(deployedAddress, salt);
    }
}

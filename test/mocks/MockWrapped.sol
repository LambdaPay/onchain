// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IWrapped} from "../../contracts/interfaces/IWrapped.sol";

/**
 * @title MockWrapped
 * @dev A mock wrapped native token (like WETH) for testing
 */
contract MockWrapped is ERC20, IWrapped {
    constructor() ERC20("Wrapped Native", "WNATIVE") {}

    /**
     * @dev Deposit native currency to get wrapped tokens
     */
    function deposit() external payable override {
        _mint(msg.sender, msg.value);
    }

    /**
     * @dev Withdraw native currency by burning wrapped tokens
     * @param amount The amount of wrapped tokens to burn
     */
    function withdraw(uint256 amount) external override {
        _burn(msg.sender, amount);
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "MockWrapped: ETH transfer failed");
    }

    /**
     * @dev Mint tokens to the specified address (only for testing)
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockERC20} from "./MockERC20.sol";

/**
 * @title MockFeeOnTransferToken
 * @dev Mock ERC20 token that takes a fee on each transfer, to test LambdaPay's protection against non-standard tokens.
 */
contract MockFeeOnTransferToken is MockERC20 {
    uint256 public transferFeePercentage; // in basis points (1/100 of a percent)

    constructor(string memory name, string memory symbol, uint8 decimals, uint256 feePercentage)
        MockERC20(name, symbol, decimals)
    {
        require(feePercentage <= 10000, "Fee too high"); // Max 100%
        transferFeePercentage = feePercentage;
    }

    /**
     * @dev Override transfer to take a fee
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * transferFeePercentage) / 10000;
        uint256 actualAmount = amount - fee;

        // Burn the fee (remove from circulation)
        _burn(msg.sender, fee);

        // Transfer the rest
        return super.transfer(to, actualAmount);
    }

    /**
     * @dev Override transferFrom to take a fee
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * transferFeePercentage) / 10000;
        uint256 actualAmount = amount - fee;

        // Burn the fee (remove from circulation)
        _burn(from, fee);

        // Transfer the rest
        return super.transferFrom(from, to, actualAmount);
    }
}

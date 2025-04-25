// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockERC20} from "./MockERC20.sol";

/**
 * @title MockRebasingToken
 * @dev Mock ERC20 token that simulates rebasing tokens like Ampleforth or aTokens.
 * This implementation adds bonus tokens on transfer to simulate rebasing.
 */
contract MockRebasingToken is MockERC20 {
    uint256 public rebaseMultiplier = 100; // 100% = no change

    constructor(string memory name, string memory symbol, uint8 decimals) MockERC20(name, symbol, decimals) {}

    /**
     * @dev Set the rebase multiplier (percentage in basis points)
     * e.g., 105 = 1.05x per transfer (5% increase)
     */
    function setRebaseMultiplier(uint256 _multiplier) external {
        rebaseMultiplier = _multiplier;
    }

    /**
     * @dev Override transfer to add bonus tokens to the recipient
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        // Add bonus tokens to simulate rebasing
        uint256 bonusAmount = (amount * (rebaseMultiplier - 100)) / 100;

        // Transfer the requested amount
        bool success = super.transfer(to, amount);

        // If transfer successful and bonus is positive, mint bonus tokens directly to recipient
        if (success && bonusAmount > 0) {
            _mint(to, bonusAmount);
        }

        return success;
    }

    /**
     * @dev Override transferFrom to add bonus tokens to the recipient
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Add bonus tokens to simulate rebasing
        uint256 bonusAmount = (amount * (rebaseMultiplier - 100)) / 100;

        // Transfer the requested amount
        bool success = super.transferFrom(from, to, amount);

        // If transfer successful and bonus is positive, mint bonus tokens directly to recipient
        if (success && bonusAmount > 0) {
            _mint(to, bonusAmount);
        }

        return success;
    }
}

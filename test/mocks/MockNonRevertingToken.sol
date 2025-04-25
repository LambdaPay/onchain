// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockERC20} from "./MockERC20.sol";

/**
 * @title MockNonRevertingToken
 * @dev Mock ERC20 token that returns false instead of reverting on transfer failure.
 * This tests LambdaPay's ability to handle tokens that don't follow the revert-on-failure pattern.
 */
contract MockNonRevertingToken is MockERC20 {
    mapping(address => bool) public blacklisted;

    constructor(string memory name, string memory symbol, uint8 decimals) MockERC20(name, symbol, decimals) {}

    /**
     * @dev Add an address to the blacklist
     */
    function blacklist(address account) external {
        blacklisted[account] = true;
    }

    /**
     * @dev Override transfer to return false instead of reverting when sender is blacklisted
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (blacklisted[msg.sender]) {
            return false;
        }
        return super.transfer(to, amount);
    }

    /**
     * @dev Override transferFrom to return false instead of reverting when from address is blacklisted
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (blacklisted[from]) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }
}

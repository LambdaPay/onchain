// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IWrapped Interface
 * @notice Defines the interface for wrapped native currency tokens (e.g., WETH, WPOL).
 * @dev Extends the standard IERC20 interface with functions specific to wrapping and unwrapping native currency.
 */
interface IWrapped is IERC20 {
    /**
     * @notice Deposits native currency (`msg.value`) into the contract and mints an equivalent amount of wrapped tokens to the caller (`msg.sender`).
     * @dev Must be called with `msg.value > 0`. Emits a {Transfer} event with `from` as the zero address.
     */
    function deposit() external payable;

    /**
     * @notice Burns `amount` of wrapped tokens from the caller (`msg.sender`) and sends an equivalent amount of native currency back to the caller.
     * @dev Requires the caller to have at least `amount` of wrapped tokens. Emits a {Transfer} event with `to` as the zero address.
     * @param amount The amount of wrapped tokens to withdraw (unwrap).
     */
    function withdraw(uint256 amount) external;
}

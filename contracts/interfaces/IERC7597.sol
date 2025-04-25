// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC2612.sol"; // Standard EIP-2612 interface

/**
 * @title IERC7597 Interface
 * @notice Extends EIP-2612 to potentially define additional permit-related functionalities or variations.
 * @dev This interface inherits all functions from IERC2612 (`permit` with split v, r, s, `nonces`, `DOMAIN_SEPARATOR`).
 *      It also explicitly declares a `permit` function that accepts a packed signature (`bytes memory signature`).
 *      Tokens implementing this might support one or both permit signature formats.
 *      ERC7597 itself is primarily focused on non-transferrable NFT roles, so its direct applicability here
 *      might be specific to a custom implementation referencing its name or standard.
 *      If the intent is purely to support packed signatures for EIP-2612, simply using IERC2612 and handling
 *      signature splitting/packing off-chain or via helper libraries might be sufficient.
 *      This interface definition assumes a token wants to explicitly signal support for the packed signature permit.
 */
interface IERC7597 is IERC2612 {
    /**
     * @notice Grants `spender` an allowance of `value` tokens from `owner`, authorized by `signature`.
     * @dev This version of permit accepts a concatenated `bytes memory signature` (e.g., r, s, v)
     *      as opposed to the split v, r, s parameters in the standard {IERC2612-permit}.
     *      Implementers must ensure the signature is valid for the given parameters against the EIP-712 domain separator.
     *      MUST revert if `deadline` is met.
     *      MUST revert if the signature is invalid or does not recover to `owner`.
     *      MUST increment the owner's nonce upon successful execution.
     *      Emits an {Approval} event.
     * @param owner The address of the token owner granting the allowance.
     * @param spender The address authorized to spend the tokens.
     * @param value The amount of tokens to allow.
     * @param deadline The Unix timestamp after which the signature expires.
     * @param signature A packed EIP-712 signature (e.g., r + s + v) provided by the owner.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature // Packed signature (r, s, v)
    ) external;

    // Note: Inherits the following from IERC2612:
    // function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    // function nonces(address owner) external view returns (uint256);
    // function DOMAIN_SEPARATOR() external view returns (bytes32);
}

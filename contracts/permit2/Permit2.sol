// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignatureTransfer} from "@lambdapay/onchain/contracts/permit2/SignatureTransfer.sol";
import {AllowanceTransfer} from "@lambdapay/onchain/contracts/permit2/AllowanceTransfer.sol";

/// @notice Permit2 handles signature-based transfers in SignatureTransfer and allowance-based transfers in AllowanceTransfer.
/// @dev Users must approve Permit2 before calling any of the transfer functions.
contract Permit2 is SignatureTransfer, AllowanceTransfer {
// Permit2 unifies the two contracts so users have maximal flexibility with their approval.
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title MockERC20Permit
 * @dev A mock ERC20 token with EIP-2612 permit support for testing
 */
contract MockERC20Permit is ERC20, ERC20Permit {
    uint8 private _decimals;
    mapping(address => bool) private _permitSettings;
    address private _mockSpender;
    uint256 private _mockValue;
    uint256 private _mockDeadline;
    uint256 private _mockNonce;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) ERC20Permit(name) {
        _decimals = decimals_;
    }

    /**
     * @dev Returns the number of decimals used for the token
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Mints tokens to the specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from the specified address
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

    /**
     * @dev Sets up the mock to accept a specific permit call
     * @param owner The owner address in the permit call
     * @param spender The spender address in the permit call
     * @param value The value in the permit call
     * @param deadline The deadline in the permit call
     * @param nonce The expected current nonce of the owner
     */
    function mockPermitSet(address owner, address spender, uint256 value, uint256 deadline, uint256 nonce) public {
        require(nonce == super.nonces(owner), "Incorrect nonce");
        _permitSettings[owner] = true;
        _mockSpender = spender;
        _mockValue = value;
        _mockDeadline = deadline;
    }

    /**
     * @dev Override permit function to use our mock settings
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
        override
    {
        // Check if we have mock settings for this owner
        if (_permitSettings[owner]) {
            require(spender == _mockSpender, "Unexpected spender");
            require(value == _mockValue, "Unexpected value");
            require(deadline == _mockDeadline, "Unexpected deadline");

            // Mock the permit effect (increment nonce and set allowance)
            unchecked {
                _useNonce(owner);
            }
            _approve(owner, spender, value);

            // Reset mock settings
            _permitSettings[owner] = false;
        } else {
            // Call the real permit function
            super.permit(owner, spender, value, deadline, v, r, s);
        }
    }

    /**
     * @dev Add a convenience method for the compact bytes signature
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature) public {
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        permit(owner, spender, value, deadline, v, r, s);
    }
}

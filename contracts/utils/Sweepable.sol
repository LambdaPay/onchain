// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Sweepable Contract Utility
 * @author Based on common patterns (e.g., OpenZeppelin AccessControl)
 * @notice Provides functionality for a designated 'sweeper' role (controlled by the owner)
 *         to withdraw ETH or ERC20 tokens that may have been accidentally sent directly to this contract address.
 * @dev This is intended for recovering funds that are *not* part of the contract's normal operational balances
 *      (e.g., user deposits meant for specific functions). It prevents funds from being permanently locked.
 *      Inherit this contract to add sweeping capabilities.
 */
abstract contract Sweepable is Context, Ownable {
    using SafeERC20 for IERC20;

    // --- Events ---

    /**
     * @notice Emitted when the sweeper address is changed by the owner.
     * @param oldSweeper The previous sweeper address.
     * @param newSweeper The new sweeper address.
     */
    event SweeperChanged(address indexed oldSweeper, address indexed newSweeper);

    /**
     * @notice Emitted when funds are successfully swept from the contract.
     * @param sweeper The address that initiated the sweep operation.
     * @param token The address of the token swept (`address(0)` for native ETH).
     * @param destination The address the funds were sent to.
     * @param amount The amount of tokens or ETH swept.
     */
    event SweepPerformed(address indexed sweeper, address indexed token, address indexed destination, uint256 amount);

    // --- Errors ---
    // (Using require messages for simplicity, could be custom errors)
    // error NotSweeper();
    // error ZeroAddress();
    // error ZeroBalance();
    // error InsufficientBalance();
    // error ETHTransferFailed();

    // --- State ---

    /**
     * @dev The address authorized to perform sweep operations. Managed by the contract owner.
     */
    address private _sweeper;

    // --- Modifiers ---

    /**
     * @dev Throws if the caller is not the currently set sweeper address.
     */
    modifier onlySweeper() {
        require(sweeper() == _msgSender(), "Sweepable: Caller is not the sweeper");
        _;
    }

    /**
     * @dev Throws if the provided address `a` is the zero address. Used for destination checks.
     */
    modifier notZero(address a) {
        require(a != address(0), "Sweepable: Address cannot be zero");
        _;
    }

    // --- Views ---

    /**
     * @notice Returns the current sweeper address.
     * @return The address currently assigned the sweeper role.
     */
    function sweeper() public view virtual returns (address) {
        return _sweeper;
    }

    // --- External Functions ---

    /**
     * @notice Sets or changes the sweeper address. Only callable by the contract owner.
     * @dev Setting to the zero address effectively disables the sweep functionality until a new sweeper is set.
     *      Emits a {SweeperChanged} event.
     * @param newSweeper The address to grant the sweeper role. Cannot be the zero address (use `renounceSweeper` if explicit renouncing is needed, or simply set to a dead address if desired).
     */
    function setSweeper(address newSweeper) public virtual onlyOwner notZero(newSweeper) {
        address oldSweeper = _sweeper;
        _sweeper = newSweeper;
        emit SweeperChanged(oldSweeper, newSweeper);
    }

    /**
     * @notice Allows the sweeper to withdraw the *entire* native ETH balance held by this contract.
     * @dev Useful for recovering ETH accidentally sent to the contract address.
     *      Requires `address(this).balance > 0`. Emits {SweepPerformed}.
     * @param destination The payable address to receive the swept ETH. Cannot be the zero address.
     */
    function sweepETH(address payable destination) public virtual onlySweeper notZero(destination) {
        uint256 balance = address(this).balance;
        require(balance > 0, "Sweepable: No ETH balance to sweep");
        (bool success,) = destination.call{value: balance}("");
        require(success, "Sweepable: ETH transfer failed");
        emit SweepPerformed(_msgSender(), address(0), destination, balance);
    }

    /**
     * @notice Allows the sweeper to withdraw a specific `amount` of native ETH held by this contract.
     * @dev Useful for partial recovery or when the exact accidental amount is known.
     *      Requires `address(this).balance >= amount`. Emits {SweepPerformed}.
     * @param destination The payable address to receive the swept ETH. Cannot be the zero address.
     * @param amount The amount of ETH to sweep.
     */
    function sweepETHAmount(address payable destination, uint256 amount)
        public
        virtual
        onlySweeper
        notZero(destination)
    {
        uint256 balance = address(this).balance;
        require(balance >= amount, "Sweepable: Insufficient ETH balance");
        require(amount > 0, "Sweepable: Amount must be greater than zero");
        (bool success,) = destination.call{value: amount}("");
        require(success, "Sweepable: ETH transfer failed");
        emit SweepPerformed(_msgSender(), address(0), destination, amount);
    }

    /**
     * @notice Allows the sweeper to withdraw the *entire* balance of a specific ERC20 token held by this contract.
     * @dev Useful for recovering ERC20 tokens accidentally sent to the contract address.
     *      Requires the contract's balance of the token to be greater than 0. Emits {SweepPerformed}.
     * @param _token The address of the ERC20 token contract to sweep.
     * @param destination The address to receive the swept tokens. Cannot be the zero address.
     */
    function sweepToken(address _token, address destination)
        public
        virtual
        onlySweeper
        notZero(destination)
        notZero(_token)
    {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Sweepable: No token balance to sweep");
        token.safeTransfer(destination, balance);
        emit SweepPerformed(_msgSender(), _token, destination, balance);
    }

    /**
     * @notice Allows the sweeper to withdraw a specific `amount` of an ERC20 token held by this contract.
     * @dev Useful for partial recovery or when the exact accidental amount is known.
     *      Requires the contract's balance of the token to be greater than or equal to `amount`. Emits {SweepPerformed}.
     * @param _token The address of the ERC20 token contract to sweep.
     * @param destination The address to receive the swept tokens. Cannot be the zero address.
     * @param amount The amount of the token to sweep.
     */
    function sweepTokenAmount(address _token, address destination, uint256 amount)
        public
        virtual
        onlySweeper
        notZero(destination)
        notZero(_token)
    {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Sweepable: Insufficient token balance");
        require(amount > 0, "Sweepable: Amount must be greater than zero");
        token.safeTransfer(destination, amount);
        emit SweepPerformed(_msgSender(), _token, destination, amount);
    }
}

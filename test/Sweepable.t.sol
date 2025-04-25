// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LambdaPay, TransferIntent} from "../contracts/LambdaPay.sol";
import {ILambdaPay} from "../contracts/interfaces/ILambdaPay.sol";
import {IWrapped} from "../contracts/interfaces/IWrapped.sol";
import {Permit2} from "../contracts/permit2/Permit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWrapped} from "./mocks/MockWrapped.sol";
import {MockUniversalRouter} from "./mocks/MockUniversalRouter.sol";

/**
 * @title SweepableTest
 * @dev Tests the Sweepable utility functionality in LambdaPay contract
 */
contract SweepableTest is Test {
    // Contract instances
    LambdaPay public lambdaPay;
    MockERC20 public token;
    MockWrapped public wrappedNative;
    Permit2 public permit2;
    MockUniversalRouter public mockRouter;

    // Test accounts
    address public owner;
    address public operator;
    address public operatorFeeDestination;
    address public merchant;
    address public payer;
    address public sweeper;
    address public recipient;

    // Constants
    uint256 public constant INITIAL_BALANCE = 100 ether;

    // Events to test
    event SweeperChanged(address indexed oldSweeper, address indexed newSweeper);

    event SweepPerformed(address indexed sweeper, address indexed token, address indexed destination, uint256 amount);

    function setUp() public {
        // Create test accounts
        owner = makeAddr("owner");
        operator = makeAddr("operator");
        operatorFeeDestination = makeAddr("operatorFeeDestination");
        merchant = makeAddr("merchant");
        payer = makeAddr("payer");
        sweeper = makeAddr("sweeper");
        recipient = makeAddr("recipient");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST", 18);
        wrappedNative = new MockWrapped();
        permit2 = new Permit2();
        mockRouter = new MockUniversalRouter(wrappedNative);

        // Deploy LambdaPay contract with owner
        vm.startPrank(owner);
        lambdaPay = new LambdaPay(
            IUniversalRouter(address(mockRouter)),
            permit2,
            operator,
            operatorFeeDestination,
            wrappedNative,
            "LambdaPay",
            "1"
        );
        vm.stopPrank();

        // Fund test accounts
        vm.deal(address(lambdaPay), 10 ether);
        token.mint(address(lambdaPay), INITIAL_BALANCE);

        // Label addresses for better trace output
        vm.label(address(lambdaPay), "LambdaPay");
        vm.label(address(token), "TestToken");
        vm.label(address(wrappedNative), "WrappedNative");
        vm.label(owner, "Owner");
        vm.label(operator, "Operator");
        vm.label(sweeper, "Sweeper");
        vm.label(recipient, "Recipient");
    }

    /**
     * @dev Tests setting a sweeper by the owner
     */
    function test_setSweeper() public {
        // Initially sweeper should be address(0)
        assertEq(lambdaPay.sweeper(), address(0), "Initial sweeper should be zero address");

        // Set sweeper as owner
        vm.startPrank(owner);

        // Expect SweeperChanged event
        vm.expectEmit(true, true, false, true, address(lambdaPay));
        emit SweeperChanged(address(0), sweeper);

        lambdaPay.setSweeper(sweeper);
        vm.stopPrank();

        // Verify sweeper was set correctly
        assertEq(lambdaPay.sweeper(), sweeper, "Sweeper not set correctly");
    }

    /**
     * @dev Tests that non-owner cannot set sweeper
     */
    function test_revertWhen_nonOwnerSetsSweeper() public {
        // Try to set sweeper as non-owner
        vm.startPrank(payer);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", payer));
        lambdaPay.setSweeper(sweeper);
        vm.stopPrank();
    }

    /**
     * @dev Tests sweeping ETH from the contract
     */
    function test_sweepETH() public {
        // Set the sweeper
        vm.startPrank(owner);
        lambdaPay.setSweeper(sweeper);
        vm.stopPrank();

        // Get initial balances
        uint256 initialContractBalance = address(lambdaPay).balance;
        uint256 initialRecipientBalance = recipient.balance;

        // Sweep ETH as sweeper
        vm.startPrank(sweeper);

        // Expect SweepPerformed event
        vm.expectEmit(true, true, true, true, address(lambdaPay));
        emit SweepPerformed(sweeper, address(0), recipient, initialContractBalance);

        lambdaPay.sweepETH(payable(recipient));
        vm.stopPrank();

        // Verify balances after sweep
        assertEq(address(lambdaPay).balance, 0, "Contract should have 0 ETH after sweep");
        assertEq(
            recipient.balance, initialRecipientBalance + initialContractBalance, "Recipient should receive swept ETH"
        );
    }

    /**
     * @dev Tests sweeping a specific amount of ETH from the contract
     */
    function test_sweepETHAmount() public {
        // Set the sweeper
        vm.startPrank(owner);
        lambdaPay.setSweeper(sweeper);
        vm.stopPrank();

        // Get initial balances
        uint256 initialContractBalance = address(lambdaPay).balance;
        uint256 initialRecipientBalance = recipient.balance;
        uint256 amountToSweep = 5 ether;

        // Sweep ETH as sweeper
        vm.startPrank(sweeper);

        // Expect SweepPerformed event
        vm.expectEmit(true, true, true, true, address(lambdaPay));
        emit SweepPerformed(sweeper, address(0), recipient, amountToSweep);

        lambdaPay.sweepETHAmount(payable(recipient), amountToSweep);
        vm.stopPrank();

        // Verify balances after sweep
        assertEq(
            address(lambdaPay).balance,
            initialContractBalance - amountToSweep,
            "Contract should have reduced ETH after partial sweep"
        );
        assertEq(
            recipient.balance, initialRecipientBalance + amountToSweep, "Recipient should receive swept ETH amount"
        );
    }

    /**
     * @dev Tests sweeping ERC20 tokens from the contract
     */
    function test_sweepToken() public {
        // Set the sweeper
        vm.startPrank(owner);
        lambdaPay.setSweeper(sweeper);
        vm.stopPrank();

        // Get initial balances
        uint256 initialContractBalance = token.balanceOf(address(lambdaPay));
        uint256 initialRecipientBalance = token.balanceOf(recipient);

        // Sweep tokens as sweeper
        vm.startPrank(sweeper);

        // Expect SweepPerformed event
        vm.expectEmit(true, true, true, true, address(lambdaPay));
        emit SweepPerformed(sweeper, address(token), recipient, initialContractBalance);

        lambdaPay.sweepToken(address(token), recipient);
        vm.stopPrank();

        // Verify balances after sweep
        assertEq(token.balanceOf(address(lambdaPay)), 0, "Contract should have 0 tokens after sweep");
        assertEq(
            token.balanceOf(recipient),
            initialRecipientBalance + initialContractBalance,
            "Recipient should receive swept tokens"
        );
    }

    /**
     * @dev Tests sweeping a specific amount of ERC20 tokens from the contract
     */
    function test_sweepTokenAmount() public {
        // Set the sweeper
        vm.startPrank(owner);
        lambdaPay.setSweeper(sweeper);
        vm.stopPrank();

        // Get initial balances
        uint256 initialContractBalance = token.balanceOf(address(lambdaPay));
        uint256 initialRecipientBalance = token.balanceOf(recipient);
        uint256 amountToSweep = 50 ether;

        // Sweep tokens as sweeper
        vm.startPrank(sweeper);

        // Expect SweepPerformed event
        vm.expectEmit(true, true, true, true, address(lambdaPay));
        emit SweepPerformed(sweeper, address(token), recipient, amountToSweep);

        lambdaPay.sweepTokenAmount(address(token), recipient, amountToSweep);
        vm.stopPrank();

        // Verify balances after sweep
        assertEq(
            token.balanceOf(address(lambdaPay)),
            initialContractBalance - amountToSweep,
            "Contract should have reduced tokens after partial sweep"
        );
        assertEq(
            token.balanceOf(recipient),
            initialRecipientBalance + amountToSweep,
            "Recipient should receive swept token amount"
        );
    }

    /**
     * @dev Tests that non-sweeper cannot sweep tokens or ETH
     */
    function test_revertWhen_nonSweeperSweeps() public {
        // Set the sweeper
        vm.startPrank(owner);
        lambdaPay.setSweeper(sweeper);
        vm.stopPrank();

        // Try to sweep as non-sweeper
        vm.startPrank(payer);
        vm.expectRevert("Sweepable: Caller is not the sweeper");
        lambdaPay.sweepETH(payable(recipient));

        vm.expectRevert("Sweepable: Caller is not the sweeper");
        lambdaPay.sweepToken(address(token), recipient);
        vm.stopPrank();
    }

    /**
     * @dev Tests that sweeping errors when no ETH/tokens are available
     */
    function test_revertWhen_noBalanceToSweep() public {
        // Create a new contract with no funds
        vm.startPrank(owner);
        LambdaPay emptyContract = new LambdaPay(
            IUniversalRouter(address(mockRouter)),
            permit2,
            operator,
            operatorFeeDestination,
            wrappedNative,
            "LambdaPay",
            "1"
        );
        emptyContract.setSweeper(sweeper);
        vm.stopPrank();

        // Try to sweep from empty contract
        vm.startPrank(sweeper);
        vm.expectRevert("Sweepable: No ETH balance to sweep");
        emptyContract.sweepETH(payable(recipient));

        vm.expectRevert("Sweepable: No token balance to sweep");
        emptyContract.sweepToken(address(token), recipient);
        vm.stopPrank();
    }
}

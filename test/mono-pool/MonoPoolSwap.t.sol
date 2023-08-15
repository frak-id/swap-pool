// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { EncoderLib } from "src/encoder/EncoderLib.sol";
import { MonoPool } from "src/MonoPool.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { BaseMonoPoolTest } from "./BaseMonoPoolTest.sol";

/// @dev Generic contract to test swap on the mono pool
/// @author KONFeature <https://github.com/KONFeature>
contract MonoPoolSwapTest is BaseMonoPoolTest {
    using EncoderLib for bytes;

    /// @dev The pool we will test
    MonoPool private pool;

    // The amount to swap
    uint256 constant swapAmount = 1.8 ether;

    function setUp() public {
        _initBaseMonoPoolTest();

        // Replace token 1 with wrapped token 1
        token1 = wToken1;
        // Build our pool
        pool = new MonoPool(address(token0), address(wToken1), bps, feeReceiver, protocolFee);
        // Append a bit of liquidity to the pool
        _addLiquidity(pool, 1000 ether, 300 ether);
    }

    /// @dev Test swapping token 0 to token 1 with send and receive all
    function test_swap0to1_ReceiveAll_SendAll_ok() public swap0to1Context {
        // Build the swap op
        bytes memory program = _buildSwapViaAll(true, swapAmount, swapUser, false);

        vm.prank(swapUser);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);
        _assertBalancePost0to1(false);
    }

    /// @dev Test swapping token 0 to token 1 with send and receive all
    function test_swap0to1_ReceiveAll_SendAll_NativeDst_ok() public swap0to1Context {
        // Build the swap op
        bytes memory program = _buildSwapViaAll(true, swapAmount, swapUser, true);

        vm.prank(swapUser);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);
        _assertBalancePost0to1(true);
    }

    /// @dev Test swapping token 0 to token 1 with direct receive
    function test_swap0to1_ReceiveAll_SendAllLimits_ok() public swap0to1Context {
        vm.pauseGasMetering();
        uint256 estimateOutput = pool.estimateSwap(swapAmount, true);
        vm.resumeGasMetering();

        // Build the swap op
        bytes memory program = _buildSwapViaAllAndSendLimits(
            BuildSwapWithAllAndLimitsParams(true, swapAmount, swapUser, false, estimateOutput, estimateOutput)
        );

        vm.prank(swapUser);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);
        _assertBalancePost0to1(false);
    }

    /// @dev Test swapping token 0 to token 1 with direct receive
    function test_swap0to1_ReceiveAll_SendAllLimits_NativeDst_ok() public swap0to1Context {
        vm.pauseGasMetering();
        uint256 estimateOutput = pool.estimateSwap(swapAmount, true);
        vm.resumeGasMetering();

        // Build the swap op
        bytes memory program = _buildSwapViaAllAndSendLimits(
            BuildSwapWithAllAndLimitsParams(true, swapAmount, swapUser, true, estimateOutput, estimateOutput)
        );

        vm.prank(swapUser);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);
        _assertBalancePost0to1(true);
    }

    /// @dev Test swapping token 0 to token 1 with direct receive
    function test_swap0to1_ReceiveDirect_SendAll_ok() public swap0to1Context {
        // Build the swap op
        bytes memory program = _buildSwapViaDirectReceive(true, swapAmount, swapUser, false, false);

        vm.prank(swapUser);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);
        _assertBalancePost0to1(false);
    }

    /// @dev Test swapping token 0 to token 1 with direct receive
    function test_swap0to1_ReceiveDirect_SendAll_NativeDst_ok() public swap0to1Context {
        // Build the swap op
        bytes memory program = _buildSwapViaDirectReceive(true, swapAmount, swapUser, false, true);

        vm.prank(swapUser);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);
        _assertBalancePost0to1(true);
    }

    /// @dev Test swapping token 0 to token 1
    function test_swap0to1_ReceiveDirect_SendDirect_ok() public swap0to1Context {
        // Get the swap output
        uint256 swapOutput = pool.estimateSwap(swapAmount, true);
        // Build the swap op
        bytes memory program = _buildSwapViaDirectReceiveAndSend(
            BuildSwapWithDirectReceiveAndSend(true, swapAmount, swapOutput, swapUser, false, false)
        );

        vm.prank(swapUser);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);
        _assertBalancePost0to1(false);
    }

    /// @dev Test swapping token 0 to token 1
    function test_swap0to1_ReceiveDirect_SendDirect_NativeDst_ok() public swap0to1Context {
        // Get the swap output
        uint256 swapOutput = pool.estimateSwap(swapAmount, true);
        // Build the swap op
        bytes memory program = _buildSwapViaDirectReceiveAndSend(
            BuildSwapWithDirectReceiveAndSend(true, swapAmount, swapOutput, swapUser, false, true)
        );

        vm.prank(swapUser);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);
        _assertBalancePost0to1(true);
    }

    /// @dev Test swapping token 1 to 0 with wrap
    function test_swap1to0_ReceiveDirect_SendDirect_NativeSrc_ok() public swap1to0Context(false) {
        // Get the swap output
        uint256 swapOutput = pool.estimateSwap(swapAmount, false);
        // Build the swap op
        bytes memory program = _buildSwapViaDirectReceiveAndSend(
            BuildSwapWithDirectReceiveAndSend(false, swapAmount, swapOutput, swapUser, true, false)
        );

        vm.prank(swapUser);
        pool.execute{ value: swapAmount }(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);
        _assertBalancePost1to0();
    }

    /* -------------------------------------------------------------------------- */
    /*                          Some generic assertion's                          */
    /* -------------------------------------------------------------------------- */

    /// @dev Assert the balance has been updated
    function _assertBalancePost0to1(bool isNativeDst) internal {
        // Ensure the user doesn't have token0 anymore
        assertEq(token0.balanceOf(swapUser), 0);
        // And that his balance of token 1 has increase
        if (isNativeDst) {
            assertGt(swapUser.balance, 0);
        } else {
            assertGt(token1.balanceOf(swapUser), 0);
        }
    }
    /// @dev Assert the balance has been updated

    function _assertBalancePost1to0() internal {
        // Ensure the user doesn't have token0 anymore
        assertEq(token1.balanceOf(swapUser), 0);
        assertEq(swapUser.balance, 0);
        // And that his balance of token 1 has increase
        assertGt(token0.balanceOf(swapUser), 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                     Some modifier to have some context                     */
    /* -------------------------------------------------------------------------- */

    modifier swap0to1Context() {
        // Add some token 0 to the user
        token0.mint(swapUser, swapAmount);
        // And directly approve the token 0 to the pool
        vm.prank(swapUser);
        token0.approve(address(pool), swapAmount);
        _;
    }

    modifier swap1to0Context(bool wrap) {
        // Add some token 1 to the user
        if (wrap) {
            vm.deal(swapUser, swapAmount);
            wToken1.deposit{ value: swapAmount }();
            // And directly approve the token 0 to the pool
            vm.prank(swapUser);
            token1.approve(address(pool), swapAmount);
        } else {
            vm.deal(swapUser, swapAmount);
        }
        _;
    }

    /// @dev Fuzz test of swap 0 to 1
    function test_fuzz_swap0To1_ok(uint128 _amount) public {
        uint256 amount = uint256(bound(_amount, 100, 100 ether));
        _swap0to1(pool, amount);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the user doesn't have token0 anymore
        assertEq(token0.balanceOf(swapUser), 0);
        // And that his balance of token 1 has increase
        assertGt(token1.balanceOf(swapUser), 0);
    }

    /// @dev Fuzz test of swap 0 to 1
    function test_fuzz_multiSwap_ok(uint128 _amount) public {
        uint256 amount = uint256(bound(_amount, 1 ether, 100 ether));
        _swap0to1(pool, amount);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the balance has changed
        assertEq(token0.balanceOf(swapUser), 0);
        assertGt(token1.balanceOf(swapUser), 0);
        assertLt(token1.balanceOf(swapUser), amount);

        // Swap back
        uint256 preSwapBalance = token1.balanceOf(swapUser);
        _swap1to0(pool, preSwapBalance);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the balance has changed
        assertGt(token0.balanceOf(swapUser), 0);
        uint256 postSwapBalance = token1.balanceOf(swapUser);
        // TODO: Should ensure strictly equals, new rules in the contracts
        // assertGt(preSwapBalance, postSwapBalance);
        assertGe(preSwapBalance, postSwapBalance);
    }
}

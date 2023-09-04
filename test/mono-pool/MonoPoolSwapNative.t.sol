// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { EncoderLib } from "src/encoder/EncoderLib.sol";
import { MonoPool } from "src/MonoPool.sol";
import { TokenLib } from "src/libs/TokenLib.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { BaseMonoPoolTest } from "./BaseMonoPoolTest.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @dev Generic contract to test swap with native token on the mono pool
/// @author KONFeature <https://github.com/KONFeature>
contract MonoPoolSwapNativeTest is BaseMonoPoolTest {
    using SafeTransferLib for address;
    using EncoderLib for bytes;

    /// @dev The pool we will test
    MonoPool private pool;

    function setUp() public {
        _initBaseMonoPoolTest();

        // Build our pool
        pool = new MonoPool(address(token0), address(0), bps, feeReceiver, protocolFee);

        // Disable protocol fees on it
        _disableProtocolFees(pool);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Simple swap test's                             */
    /* -------------------------------------------------------------------------- */

    /// @dev Test swapping token 0 to token 1
    function test_swap0to1_ok() public withNativeLiquidity(100 ether, 100 ether) {
        _swap0to1Native(1 ether);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the user doesn't have token0 anymore
        assertEq(token0.balanceOf(swapUser), 0);
        assertGt(swapUser.balance, 0);
    }

    /// @dev Test swapping token 0 to token 1
    function test_fuzz_swap0to1_ok(uint128 _amount) public withNativeLiquidity(100 ether, 100 ether) {
        uint256 amount = bound(uint256(_amount), 10, 100 ether);
        _swap0to1Native(amount);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the user doesn't have token0 anymore
        assertEq(token0.balanceOf(swapUser), 0);
        assertGt(swapUser.balance, 0);
    }

    /// @dev Test swapping token 1 to token 0
    function test_swap1to0_ok() public withNativeLiquidity(100 ether, 100 ether) {
        _swap1to0Native(1 ether);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the user doesn't have token0 anymore
        assertEq(swapUser.balance, 0);
        // And that his balance of token 1 has increase
        assertGt(token0.balanceOf(swapUser), 0);
    }

    /// @dev Test swapping token 1 to token 0
    function test_fuzz_swap1to0_ok(uint128 _amount) public withNativeLiquidity(100 ether, 100 ether) {
        uint256 amount = bound(uint256(_amount), 10, 100 ether);
        _swap1to0Native(amount);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the user doesn't have token0 anymore
        assertEq(swapUser.balance, 0);
        // And that his balance of token 1 has increase
        assertGt(token0.balanceOf(swapUser), 0);
    }

    /// @dev Test swapping token 1 to token 0
    function test_swap1to0_ko_InvalidTransferAmount_TooLow() public withNativeLiquidity(100 ether, 100 ether) {
        uint256 amount = 0.1 ether;

        // Mint token & approve transfer
        vm.deal(swapUser, amount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(false, amount)
            .appendReceive(false, amount)
            .appendSendAll(true, swapUser)
            .done();

        // Send it
        vm.expectRevert(TokenLib.InvalidNativeTransferAmount.selector);
        vm.prank(swapUser);
        pool.execute{ value: amount - 1 }(program);

        // Ensure the user balance hasn't changes
        assertEq(swapUser.balance, amount);
    }

    /// @dev Test swapping token 1 to token 0
    function test_swap1to0_ko_InvalidTransferAmount_TooHigh() public withNativeLiquidity(100 ether, 100 ether) {
        uint256 amount = 0.1 ether;

        // Mint token & approve transfer
        vm.deal(swapUser, amount * 2);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(false, amount)
            .appendReceive(false, amount)
            .appendSendAll(true, swapUser)
            .done();

        // Send it
        vm.expectRevert(TokenLib.InvalidNativeTransferAmount.selector);
        vm.prank(swapUser);
        pool.execute{ value: amount + 1 }(program);
    }

    /// @dev Test swapping token 1 to token 0
    function test_swap1to0_ok_ForceFeed() public withNativeLiquidity(100 ether, 100 ether) {
        uint256 amount = 0.1 ether;

        // Mint token & approve transfer
        vm.deal(swapUser, amount * 2);

        // Force feed some eth to the pool
        vm.prank(swapUser);
        address(pool).forceSafeTransferETH(amount, 0);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(false, amount)
            .appendReceive(false, amount)
            .appendSendAll(true, swapUser)
            .done();

        // Send it
        vm.prank(swapUser);
        pool.execute{ value: amount }(program);
    }

    /// @dev Test swapping token 1 to token 0
    function test_swap1to0_ko_NotEnoughValue() public withNativeLiquidity(100 ether, 100 ether) {
        uint256 amount = 0.1 ether;

        // Mint token & approve transfer
        vm.deal(swapUser, amount * 2);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(false, amount)
            .appendSwap(false, amount)
            .appendReceive(false, amount)
            .appendSendAll(true, swapUser)
            .done();

        // Send it
        vm.expectRevert(MonoPool.LeftOverDelta.selector);
        vm.prank(swapUser);
        pool.execute{ value: amount }(program);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Some liquidity test's                           */
    /* -------------------------------------------------------------------------- */

    /// @dev Test removing liquidity liquidity
    function test_removeNativeLiq_ok() public withNativeLiquidity(100 ether, 100 ether) {
        // Get the initial pool reserves
        (uint256 initReserve0, uint256 initReserve1) = pool.getReserves();

        // Perform a few swap's in a for loop of 50 iteration
        {
            vm.pauseGasMetering();
            for (uint256 i = 0; i < 50; i++) {
                _swap0to1Native(1 ether);
                _swap1to0Native(1 ether);
            }
            vm.resumeGasMetering();
        }

        // Get the new pool reserves
        (uint256 newReserve0, uint256 newReserve1) = pool.getReserves();

        // Ensure the reserve has increase
        assertGt(newReserve0, initReserve0);
        assertGt(newReserve1, initReserve1);

        // Withdraw the liquidity owner position
        {
            // Build the program to execute
            // forgefmt: disable-next-item
            bytes memory program = EncoderLib.init()
                .appendRemoveLiquidity(pool.getPosition(liquidityProvider))
                .appendSendAll(true, liquidityProvider)
                .appendSendAll(false, liquidityProvider)
                .done();

            // Execute it
            vm.prank(liquidityProvider);
            pool.execute(program);
        }

        // Ensure the reserve has decrease
        (uint256 finalReserve0, uint256 finalReserve1) = pool.getReserves();
        assertLt(finalReserve0, newReserve0);
        assertLt(finalReserve1, newReserve1);

        // Ensure the balance of our liquidity provider his more than what he inserted in the pool
        assertGt(token0.balanceOf(liquidityProvider), initReserve0);
        assertGt(liquidityProvider.balance, initReserve1);
    }

    /* -------------------------------------------------------------------------- */
    /*                       Helper's to swap native tokens                       */
    /* -------------------------------------------------------------------------- */

    function _swap0to1Native(uint256 swapAmount) internal {
        // Prank the eth to the user directly
        token0.mint(swapUser, swapAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), swapAmount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(true, swapAmount)
            .appendReceive(true, swapAmount)
            .appendSendAll(false, swapUser)
            .done();

        // Send it
        vm.prank(swapUser);
        pool.execute(program);
    }

    function _swap1to0Native(uint256 swapAmount) internal {
        // Mint token & approve transfer
        vm.deal(swapUser, swapAmount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(false, swapAmount)
            .appendReceive(false, swapAmount)
            .appendSendAll(true, swapUser)
            .done();

        // Send it
        vm.prank(swapUser);
        pool.execute{ value: swapAmount }(program);
    }

    modifier withNativeLiquidity(uint256 amount0, uint256 amount1) {
        // Mint some initial tokens to the liquidity provider
        token0.mint(liquidityProvider, amount0);
        vm.deal(liquidityProvider, amount1);

        // Authorise the pool to spend our tokens
        vm.startPrank(liquidityProvider);
        token0.approve(address(pool), amount1);
        vm.stopPrank();

        // Build the program to execute
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendAddLiquidity(amount0, amount1)
            .appendReceiveAll(true)
            .appendReceiveAll(false)
            .done();

        // Execute it
        vm.prank(liquidityProvider);
        pool.execute{ value: amount1 }(program);

        _;
    }
}

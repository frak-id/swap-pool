// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { EncoderLib } from "src/encoder/EncoderLib.sol";
import { MonoPool } from "src/MonoPool.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { BaseMonoPoolTest } from "./BaseMonoPoolTest.sol";

/// @dev Generic contract to test swap with native token on the mono pool
/// @author KONFeature <https://github.com/KONFeature>
/// TODO: Add all possible failing test
/// TODO: Add test on both side (token0 and token1 as native)
/// TODO: Add test with multiple op (swap + add liquidity)
/// TODO: Add test with multiple receive / send / swap in the same op
contract MonoPoolSwapNativeTest is BaseMonoPoolTest {
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

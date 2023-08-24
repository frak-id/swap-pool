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

    function setUp() public {
        _initBaseMonoPoolTest();

        // Build our pool
        pool = new MonoPool(address(token0), address(token1), bps, feeReceiver, protocolFee);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Testing send limit's                            */
    /* -------------------------------------------------------------------------- */

    /// @dev Test swapping token with limits
    function test_swapSendLimits_ok() public withLiquidity(pool, 100 ether, 100 ether) {
        uint256 baseAmount = 1 ether;

        // Mint token & approve transfer
        token0.mint(swapUser, baseAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), baseAmount);

        // Estimate the swap
        (uint256 estimateOut,,) = pool.estimateSwap(baseAmount, true);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(true, baseAmount)
            .appendReceiveAll(true)
            .appendSendAllWithLimits(false, swapUser, estimateOut, estimateOut)
            .done();

        // Send it
        vm.prank(swapUser);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the user doesn't have token0 anymore
        assertEq(token0.balanceOf(swapUser), 0);
        // And that his balance of token 1 has increase
        assertGt(token1.balanceOf(swapUser), 0);
        assertEq(token1.balanceOf(swapUser), estimateOut);
    }

    /// @dev Test swapping token with limits
    function test_swapSendLimitsWithStates_ok() public withLiquidity(pool, 2000 ether, 2000 ether) {
        uint256 baseAmount = 1 ether;

        // Estimate the swap
        (uint256 estimateOut,,) = pool.estimateSwap(baseAmount, true);
        uint256 lowEstimate = estimateOut * 95 / 100;
        uint256 highEstimate = estimateOut * 105 / 100;

        // Simulate some swap activity
        _simulateSwapActivity(pool, 100 ether);

        // Burn all of the token 1 from the user
        token1.burn(swapUser, token1.balanceOf(swapUser));

        // Mint token & approve transfer
        token0.mint(swapUser, baseAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), baseAmount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(true, baseAmount)
            .appendReceiveAll(true)
            .appendSendAllWithLimits(false, swapUser, lowEstimate, highEstimate)
            .done();

        // Send it
        vm.prank(swapUser);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Assert the received amount is inside the bounds
        assertLt(token1.balanceOf(swapUser), highEstimate);
        assertGt(token1.balanceOf(swapUser), lowEstimate);
    }

    /// @dev Test swapping token with limits
    function test_swapSendLimits_ko_AmountOutsideBounds_Low() public withLiquidity(pool, 100 ether, 100 ether) {
        uint256 baseAmount = 1 ether;

        // Mint token & approve transfer
        token1.mint(swapUser, baseAmount);
        vm.prank(swapUser);
        token1.approve(address(pool), baseAmount);

        // Estimate the swap
        (uint256 estimateOut,,) = pool.estimateSwap(baseAmount, false);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(false, baseAmount)
            .appendReceiveAll(false)
            .appendSendAllWithLimits(true, swapUser, estimateOut + 1, estimateOut)
            .done();

        // Send it
        vm.expectRevert(MonoPool.AmountOutsideBounds.selector);
        vm.prank(swapUser);
        pool.execute(program);
    }

    /// @dev Test swapping token with limits
    function test_swapSendLimits_ko_AmountOutsideBounds_High() public withLiquidity(pool, 100 ether, 100 ether) {
        uint256 baseAmount = 1 ether;

        // Mint token & approve transfer
        token0.mint(swapUser, baseAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), baseAmount);

        // Estimate the swap
        (uint256 estimateOut,,) = pool.estimateSwap(baseAmount, true);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(true, baseAmount)
            .appendReceiveAll(true)
            .appendSendAllWithLimits(false, swapUser, estimateOut, estimateOut - 1)
            .done();

        // Send it
        vm.expectRevert(MonoPool.AmountOutsideBounds.selector);
        vm.prank(swapUser);
        pool.execute(program);
    }

    /// @dev Test swapping token with limits
    function test_swapSendLimits_ko_NegativeReceive() public withLiquidity(pool, 100 ether, 100 ether) {
        uint256 baseAmount = 1 ether;

        // Mint token & approve transfer
        token0.mint(swapUser, baseAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), baseAmount);

        // Estimate the swap
        (uint256 estimateOut,,) = pool.estimateSwap(baseAmount, true);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendSwap(true, baseAmount)
            .appendSendAllWithLimits(true, swapUser, estimateOut, estimateOut)
            .done();

        // Send it
        vm.expectRevert(MonoPool.NegativeSend.selector);
        vm.prank(swapUser);
        pool.execute(program);
    }
}

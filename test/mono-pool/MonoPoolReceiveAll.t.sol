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
    /*                           Testing receive limit's                          */
    /* -------------------------------------------------------------------------- */

    /// @dev Test swapping token with limits
    function test_swapReceiveLimits_ok() public withLiquidity(pool, 100 ether, 100 ether) {
        uint256 baseAmount = 1 ether;

        // Mint token & approve transfer
        token0.mint(swapUser, baseAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), baseAmount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
                .appendSwap(true, baseAmount)
                .appendReceiveAllWithLimits(true, baseAmount, baseAmount)
                .appendSendAll(false, swapUser, false)
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
    }

    /// @dev Test swapping token with limits
    function test_swapReceiveLimits_ko_AmountOutsideBounds_Low() public withLiquidity(pool, 100 ether, 100 ether) {
        uint256 baseAmount = 1 ether;

        // Mint token & approve transfer
        token0.mint(swapUser, baseAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), baseAmount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
                .appendSwap(true, baseAmount)
                .appendReceiveAllWithLimits(true, baseAmount + 1, baseAmount)
                .appendSendAll(false, swapUser, false)
                .done();

        // Send it
        vm.expectRevert(MonoPool.AmountOutsideBounds.selector);
        vm.prank(swapUser);
        pool.execute(program);
    }

    /// @dev Test swapping token with limits
    function test_swapReceiveLimits_ko_AmountOutsideBounds_High() public withLiquidity(pool, 100 ether, 100 ether) {
        uint256 baseAmount = 1 ether;

        // Mint token & approve transfer
        token0.mint(swapUser, baseAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), baseAmount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
                .appendSwap(true, baseAmount)
                .appendReceiveAllWithLimits(true, baseAmount, baseAmount - 1)
                .appendSendAll(false, swapUser, false)
                .done();

        // Send it
        vm.expectRevert(MonoPool.AmountOutsideBounds.selector);
        vm.prank(swapUser);
        pool.execute(program);
    }

    /// @dev Test swapping token with limits
    function test_swapReceiveLimits_ko_NegativeReceive() public withLiquidity(pool, 100 ether, 100 ether) {
        uint256 baseAmount = 1 ether;

        // Mint token & approve transfer
        token0.mint(swapUser, baseAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), baseAmount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
                .appendSwap(true, baseAmount)
                .appendReceiveAllWithLimits(false, baseAmount, baseAmount)
                .done();

        // Send it
        vm.expectRevert(MonoPool.NegativeReceive.selector);
        vm.prank(swapUser);
        pool.execute(program);
    }
}

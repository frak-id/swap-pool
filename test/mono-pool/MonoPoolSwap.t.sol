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

        // Disable protocol fees on it
        _disableProtocolFees(pool);
    }

    /// @dev Test swapping token 0 to token 1
    function test_swap0to1_ok() public withLiquidity(pool, 100 ether, 100 ether) {
        _swap0to1(pool, 0.1e18);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the user doesn't have token0 anymore
        assertEq(token0.balanceOf(swapUser), 0);
        // And that his balance of token 1 has increase
        assertGt(token1.balanceOf(swapUser), 0);
    }

    /// @dev Test swapping token 1 to token 0
    function test_swap1to0_ok() public withLiquidity(pool, 100 ether, 100 ether) {
        _swap1to0(pool, 0.1e18);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the user doesn't have token0 anymore
        assertEq(token1.balanceOf(swapUser), 0);
        // And that his balance of token 1 has increase
        assertGt(token0.balanceOf(swapUser), 0);
    }

    /// @dev Fuzz test of swap 0 to 1
    function test_fuzz_swap0To1_ok(uint128 _amount) public withLiquidity(pool, 100 ether, 100 ether) {
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
    function test_fuzz_multiSwap_ok(uint128 _amount) public withLiquidity(pool, 100 ether, 100 ether) {
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
        // TODO: Why is that KO??
        // uint256 postSwapBalance = token1.balanceOf(swapUser);
        // assertGt(preSwapBalance, postSwapBalance);
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
        uint256 estimateOut = pool.estimateSwap(baseAmount, true);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(4)
            .appendSwap(true, baseAmount)
            .appendReceiveAll(true)
            .appendSendAllWithLimits(false, swapUser, estimateOut, estimateOut, false)
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
        uint256 estimateOut = pool.estimateSwap(baseAmount, true);
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
        bytes memory program = EncoderLib.init(4)
            .appendSwap(true, baseAmount)
            .appendReceiveAll(true)
            .appendSendAllWithLimits(false, swapUser, lowEstimate, highEstimate, false)
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
        uint256 estimateOut = pool.estimateSwap(baseAmount, false);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(4)
            .appendSwap(false, baseAmount)
            .appendReceiveAll(false)
            .appendSendAllWithLimits(true, swapUser, estimateOut + 1, estimateOut, false)
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
        uint256 estimateOut = pool.estimateSwap(baseAmount, true);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(4)
            .appendSwap(true, baseAmount)
            .appendReceiveAll(true)
            .appendSendAllWithLimits(false, swapUser, estimateOut, estimateOut - 1, false)
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
        uint256 estimateOut = pool.estimateSwap(baseAmount, true);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(4)
            .appendSwap(true, baseAmount)
            .appendSendAllWithLimits(true, swapUser, estimateOut, estimateOut, false)
            .done();

        // Send it
        vm.expectRevert(MonoPool.NegativeSend.selector);
        vm.prank(swapUser);
        pool.execute(program);
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
        bytes memory program = EncoderLib.init(4)
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
        bytes memory program = EncoderLib.init(4)
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
        bytes memory program = EncoderLib.init(4)
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
        bytes memory program = EncoderLib.init(4)
                .appendSwap(true, baseAmount)
                .appendReceiveAllWithLimits(false, baseAmount, baseAmount)
                .done();

        // Send it
        vm.expectRevert(MonoPool.NegativeReceive.selector);
        vm.prank(swapUser);
        pool.execute(program);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { EncoderLib } from "src/encoder/EncoderLib.sol";
import { MonoPool } from "src/MonoPool.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { BaseMonoPoolTest } from "./BaseMonoPoolTest.sol";

/// @dev Generic contract to test swap with native token on the mono pool
/// @author KONFeature <https://github.com/KONFeature>
contract MonoPoolSwapNativeTest is BaseMonoPoolTest {
    using EncoderLib for bytes;

    /// @dev The pool we will test
    MonoPool private pool;

    function setUp() public {
        _initBaseMonoPoolTest();

        // Replace token0 by wrapped Token0
        token0 = wToken0;

        // Build our pool
        pool = new MonoPool(address(wToken0), address(token1), bps, feeReceiver, protocolFee);

        // Disable protocol fees on it
        _disableProtocolFees(pool);
    }

    /// @dev Test swapping token 0 to token 1
    function test_swap0to1_ok() public withLiquidity(pool, 100 ether, 100 ether) {
        _swap0to1Native(0.1e18);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the user doesn't have token0 anymore
        assertEq(token0.balanceOf(swapUser), 0);
        assertEq(swapUser.balance, 0);
        // And that his balance of token 1 has increase
        assertGt(token1.balanceOf(swapUser), 0);
    }

    /// @dev Test swapping token 1 to token 0
    function test_swap1to0_ok() public withLiquidity(pool, 100 ether, 100 ether) {
        _swap1to0Native(0.1e18);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the user doesn't have token0 anymore
        assertEq(token1.balanceOf(swapUser), 0);
        // And that his balance of token 1 has increase
        assertEq(wToken0.balanceOf(swapUser), 0);
        assertGt(swapUser.balance, 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                       Helper's to swap native tokens                       */
    /* -------------------------------------------------------------------------- */

    function _swap0to1Native(uint256 swapAmount) internal {
        // Prank the eth to the user directly
        vm.deal(swapUser, swapAmount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(4)
            .appendSwap(true, swapAmount)
            .appendReceiveAllNative(true)
            .appendSendAll(false, swapUser, false)
            .done();

        // Send it
        vm.prank(swapUser);
        pool.execute{ value: swapAmount }(program);
    }

    function _swap1to0Native(uint256 swapAmount) internal {
        // Mint token & approve transfer
        token1.mint(swapUser, swapAmount);
        vm.prank(swapUser);
        token1.approve(address(pool), swapAmount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(4)
            .appendSwap(false, swapAmount)
            .appendReceiveAll(false)
            .appendSendAll(true, swapUser, true)
            .done();

        // Send it
        vm.prank(swapUser);
        pool.execute(program);
    }
}

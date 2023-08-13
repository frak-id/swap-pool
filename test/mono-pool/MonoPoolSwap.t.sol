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
}

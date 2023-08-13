// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { EncoderLib } from "src/encoder/EncoderLib.sol";
import { MonoPool } from "src/MonoPool.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { BaseMonoPoolTest } from "./BaseMonoPoolTest.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @dev Generic contract to test liquidity operation on the mono pool
/// @author KONFeature <https://github.com/KONFeature>
contract MonoPoolLiquidityTest is BaseMonoPoolTest {
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

    /* -------------------------------------------------------------------------- */
    /*                              Adding liquidity                              */
    /* -------------------------------------------------------------------------- */

    /// @dev Test adding liquidity
    function test_addLiquidityFromZero_ok() public {
        uint256 amountToken0 = 100e18;
        uint256 amountToken1 = amountToken0 / 3;

        _addLiquidity(pool, amountToken0, amountToken1);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the pool has pulled all the tokens
        assertEq(token0.balanceOf(address(pool)), amountToken0);
        assertEq(token1.balanceOf(address(pool)), amountToken1);

        // Ensure the pool has registered the liquidity
        (uint256 poolReserveToken0, uint256 poolReserveToken1) = pool.getReserves();
        assertEq(poolReserveToken0, amountToken0);
        assertEq(poolReserveToken1, amountToken1);
    }

    /// @dev Test adding liquidity
    function test_addLiquidityFromZero_ko_NoAllowance() public {
        uint256 amountToken0 = 100e18;
        uint256 amountToken1 = amountToken0 / 3;

        // Mint some initial tokens to the liquidity provider
        token0.mint(liquidityProvider, amountToken0);
        token1.mint(liquidityProvider, amountToken1);

        // Build the program to execute
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(3)
            .appendAddLiquidity(liquidityProvider, amountToken0, amountToken1)
            .appendReceiveAll(true)
            .appendReceiveAll(false)
            .done();

        // Execute it
        vm.prank(liquidityProvider);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        pool.execute(program);
    }

    /// @dev Test adding liquidity
    function test_addLiquidityFromZero_ko_InsuficientAllowance() public {
        uint256 amountToken0 = 100e18;
        uint256 amountToken1 = amountToken0 / 3;

        // Mint some initial tokens to the liquidity provider
        token0.mint(liquidityProvider, amountToken0);
        token1.mint(liquidityProvider, amountToken1);

        // Authorise the pool to spend our tokens
        vm.startPrank(liquidityProvider);
        token0.approve(address(pool), amountToken0);
        token1.approve(address(pool), amountToken1 / 2);
        vm.stopPrank();

        // Build the program to execute
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(3)
            .appendAddLiquidity(liquidityProvider, amountToken0, amountToken1)
            .appendReceiveAll(true)
            .appendReceiveAll(false)
            .done();

        // Execute it
        vm.prank(liquidityProvider);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        pool.execute(program);
    }

    /// @dev Test adding liquidity
    function test_addLiquidityFromZero_ko_LeftOverDelta() public {
        uint256 amountToken0 = 100e18;
        uint256 amountToken1 = amountToken0 / 3;

        // Mint some initial tokens to the liquidity provider
        token0.mint(liquidityProvider, amountToken0);
        token1.mint(liquidityProvider, amountToken1);

        // Authorise the pool to spend our tokens
        vm.startPrank(liquidityProvider);
        token0.approve(address(pool), amountToken0);
        token1.approve(address(pool), amountToken1 / 2);
        vm.stopPrank();

        // Build the program to execute
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(3)
            .appendAddLiquidity(liquidityProvider, amountToken0, amountToken1)
            .appendReceiveAll(true)
            .done();

        // Execute it
        vm.prank(liquidityProvider);
        vm.expectRevert(MonoPool.LeftOverDelta.selector);
        pool.execute(program);
    }

    /// @dev Test adding liquidity
    function test_fuzz_addLiquidityFromZero_ok(uint128 _amount0, uint128 _amount1) public {
        uint256 amountToken0 = uint256(bound(_amount0, 1, 3e37));
        uint256 amountToken1 = uint256(bound(_amount1, 1, 3e37));

        _addLiquidity(pool, amountToken0, amountToken1);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the pool has pulled all the tokens
        assertEq(token0.balanceOf(address(pool)), amountToken0);
        assertEq(token1.balanceOf(address(pool)), amountToken1);

        // Ensure the pool has registered the liquidity
        (uint256 poolReserveToken0, uint256 poolReserveToken1) = pool.getReserves();
        assertEq(poolReserveToken0, amountToken0);
        assertEq(poolReserveToken1, amountToken1);
    }

    /// @dev Test adding liquidity
    function test_addLiquidity_ok() public withLiquidity(pool, 100 ether, 30 ether) {
        // The amount we want to insert
        uint256 amountToken0 = 100e18;
        uint256 amountToken1 = 100e18;

        // Get the current pool ratio between token0 and token1
        (uint256 totalLiq, uint256 poolReserveToken0, uint256 poolReserveToken1) = pool.getPoolState();

        uint256 initialPoolRatio;
        if (poolReserveToken0 > poolReserveToken1) {
            initialPoolRatio = poolReserveToken0 / poolReserveToken1;
        } else {
            initialPoolRatio = poolReserveToken1 / poolReserveToken0;
        }

        // Add the desired liquidity
        _addLiquidity(pool, amountToken0, amountToken1);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the reserve of each tokens has increase
        (uint256 newTotalLiq, uint256 newPoolReserveToken0, uint256 newPoolReserveToken1) = pool.getPoolState();
        assertGt(newTotalLiq, totalLiq);
        assertGt(newPoolReserveToken0, poolReserveToken0);
        assertGt(newPoolReserveToken1, poolReserveToken1);

        // Ensure the ratio is the same
        uint256 finalPoolRatio;
        if (poolReserveToken0 > poolReserveToken1) {
            finalPoolRatio = newPoolReserveToken0 / newPoolReserveToken1;
        } else {
            finalPoolRatio = newPoolReserveToken1 / newPoolReserveToken0;
        }
        assertEq(initialPoolRatio, finalPoolRatio);
    }

    /// @dev Test adding liquidity with fuzz
    /// @dev TODO: Disabled for now since some edge case can change the liquidity
    /// @dev TOFIX: URGENT
    function disabled_test_fuzz_addLiquidity_ok(
        uint128 _amount0,
        uint128 _amount1
    )
        public
        withLiquidity(pool, 10 ether, 3 ether)
    {
        uint256 amountToken0 = uint256(bound(_amount0, 10, 3e18));
        uint256 amountToken1 = uint256(bound(_amount1, 10, 3e18));

        // Get the current pool ratio between token0 and token1
        (uint256 totalLiq, uint256 poolReserveToken0, uint256 poolReserveToken1) = pool.getPoolState();

        uint256 initialPoolRatio;
        if (poolReserveToken0 > poolReserveToken1) {
            initialPoolRatio = poolReserveToken0 / poolReserveToken1;
        } else {
            initialPoolRatio = poolReserveToken1 / poolReserveToken0;
        }

        // Add the desired liquidity
        _addLiquidity(pool, amountToken0, amountToken1);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the reserve of each tokens has increase
        (uint256 newTotalLiq, uint256 newPoolReserveToken0, uint256 newPoolReserveToken1) = pool.getPoolState();
        assertGt(newTotalLiq, totalLiq);
        assertGt(newPoolReserveToken0, poolReserveToken0);
        assertGt(newPoolReserveToken1, poolReserveToken1);

        // Ensure the ratio is the same
        uint256 finalPoolRatio;
        if (poolReserveToken0 > poolReserveToken1) {
            finalPoolRatio = newPoolReserveToken0 / newPoolReserveToken1;
        } else {
            finalPoolRatio = newPoolReserveToken1 / newPoolReserveToken0;
        }
        assertEq(initialPoolRatio, finalPoolRatio);
    }
}

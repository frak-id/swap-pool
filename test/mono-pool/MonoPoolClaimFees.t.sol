// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { EncoderLib } from "src/encoder/EncoderLib.sol";
import { MonoPool } from "src/MonoPool.sol";
import { PoolLib } from "src/libs/PoolLib.sol";
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
    }

    /* -------------------------------------------------------------------------- */
    /*                                Claiming fees                               */
    /* -------------------------------------------------------------------------- */

    /// @dev Test with a free pool, so no fees to claim
    function test_claimNoFees_ok() public withLiquidity(pool, 100 ether, 30 ether) {
        // Assert the pool are synced
        _assertReserveSynced(pool);
        // Build the claim only op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendClaimFees()
            .done();

        // Send it
        vm.prank(feeReceiver);
        pool.execute(program);

        // Ensure every balance is still to 0
        assertEq(token0.balanceOf(feeReceiver), 0);
        assertEq(token1.balanceOf(feeReceiver), 0);
    }

    /// @dev Test adding liquidity
    function test_swapWithFees_ok() public withLiquidity(pool, 100 ether, 30 ether) {
        uint256 amountToSwap = 10 ether;
        _swap0to1(pool, amountToSwap);
        // Assert the pool are synced
        _assertReserveSynced(pool);
        // Assert we have pending fees on the token 0
        (uint256 protocolFees0,) = pool.getProtocolFees();
        assertGt(protocolFees0, 0);
        // Ensure the amount match the percent picked
        assertEq((amountToSwap * protocolFee / 10_000), protocolFees0);
    }

    /// @dev Test adding liquidity
    function test_claimFees_ok() public withLotOfState(pool) {
        uint256 prevToken0Bal = token0.balanceOf(feeReceiver);
        uint256 prevToken1Bal = token1.balanceOf(feeReceiver);

        (uint256 pFees0, uint256 pFees1) = pool.getProtocolFees();

        // Assert the user can claim his founds
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendClaimFees()
            .appendSendAll(true, feeReceiver)
            .appendSendAll(false, feeReceiver)
            .done();

        // Send it
        vm.prank(feeReceiver);
        pool.execute(program);

        // Assert the pool are synced
        _assertReserveSynced(pool);

        // Ensure the fees has changed
        (uint256 newPFees0, uint256 newPFees1) = pool.getProtocolFees();
        assertEq(newPFees0, 0);
        assertEq(newPFees1, 0);

        // Ensure user balance has increase
        uint256 newToken0Bal = token0.balanceOf(feeReceiver);
        uint256 newToken1Bal = token1.balanceOf(feeReceiver);
        assertGt(newToken0Bal, prevToken0Bal);
        assertGt(newToken1Bal, prevToken1Bal);
        assertEq(newToken0Bal, prevToken0Bal + pFees0);
        assertEq(newToken1Bal, prevToken1Bal + pFees1);
    }

    /// @dev Testing that's it's ko if the user is not the fee receiver
    function test_claimFees_ko_NotFeeReceiver() public withLotOfState(pool) {
        // Assert the user can claim his founds
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendClaimFees()
            .appendSendAll(true, feeReceiver)
            .appendSendAll(false, feeReceiver)
            .done();

        // Send it
        vm.expectRevert(MonoPool.NotFeeReceiver.selector);
        vm.prank(swapUser);
        pool.execute(program);
    }

    /* -------------------------------------------------------------------------- */
    /*                          Updating address and fees                         */
    /* -------------------------------------------------------------------------- */

    function test_updateAddressAndFees_ok() public {
        // Can update the fees amount
        uint16 newFee = 10;
        vm.prank(feeReceiver);
        pool.updateFeeReceiver(feeReceiver, newFee);

        (, uint256 pFee) = pool.getFees();
        assertEq(pFee, newFee);

        // Can set the fee to 0
        vm.prank(feeReceiver);
        pool.updateFeeReceiver(feeReceiver, 0);
        (, pFee) = pool.getFees();
        assertEq(pFee, 0);

        // Can set receive to 0 and fee to 0
        vm.prank(feeReceiver);
        pool.updateFeeReceiver(address(0), 0);
        (, pFee) = pool.getFees();
        assertEq(pFee, 0);
    }

    function test_updateAddressAndFees_ko_CantHaveFeeWith0Address() public {
        // Can't update if we keep fees and it's too the 0 address
        vm.expectRevert();
        vm.prank(feeReceiver);
        pool.updateFeeReceiver(address(0), 1);
    }

    function test_updateAddressAndFees_ko_TooLargeFee() public {
        // Can't update the fees amount is too large (5.1% here)
        vm.expectRevert();
        vm.prank(feeReceiver);
        pool.updateFeeReceiver(feeReceiver, 500);
    }

    function test_updateAddressAndFees_ko_NotTheFeeReceiver() public {
        // Can't update if it's not the fee receiver
        vm.expectRevert(MonoPool.NotFeeReceiver.selector);
        pool.updateFeeReceiver(feeReceiver, 10);
    }
}

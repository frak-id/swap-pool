// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { EncoderLib } from "src/encoder/EncoderLib.sol";
import { MonoPool } from "src/MonoPool.sol";
import { Token } from "src/libs/TokenLib.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @dev Generic contract to test mono pool, providing some helpers
/// @author KONFeature <https://github.com/KONFeature>
abstract contract BaseMonoPoolTest is Test {
    using SafeTransferLib for address;
    using EncoderLib for bytes;

    /// @dev A few tokens to use for pool construction
    MockERC20 internal token0;
    MockERC20 internal token1;

    /// @dev Our liquidity provider user
    address internal liquidityProvider;

    /// @dev The fee receiver
    address internal feeReceiver;

    /// @dev The swap user
    address internal swapUser;
    uint256 internal swapUserPrivKey;

    /// @dev base bps to use (1%)
    uint256 internal bps = 100;

    /// @dev the base protocol fees (2%)
    uint16 internal protocolFee = 200;

    /// @dev Init some var for the base mono pool test
    function _initBaseMonoPoolTest() internal {
        // Create our users
        liquidityProvider = _newUser("liquidityProvider");
        feeReceiver = _newUser("feeReceiver");
        (swapUser, swapUserPrivKey) = _newUserWithPrivKey("swapUser");

        // Create a few tokens
        token0 = _newToken("token0");
        token1 = _newToken("token1");
    }

    /// @dev Disable pool fees
    function _disableProtocolFees(MonoPool pool) internal {
        vm.prank(feeReceiver);
        pool.updateFeeReceiver(address(0), 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                 Some modifier's to get specific pool states                */
    /* -------------------------------------------------------------------------- */

    modifier outOfGasScope() {
        vm.pauseGasMetering();
        _;
        vm.resumeGasMetering();
    }

    modifier withLiquidity(MonoPool pool, uint256 amount0, uint256 amount1) {
        vm.pauseGasMetering();
        _addLiquidity(pool, amount0, amount1);
        vm.resumeGasMetering();
        _;
    }

    modifier withSwaps(MonoPool pool, uint256 initialAmount, uint256 swapCount) {
        vm.pauseGasMetering();
        _multipleSwap(pool, initialAmount, swapCount);
        vm.resumeGasMetering();
        _;
    }

    modifier withLotOfState(MonoPool pool) {
        vm.pauseGasMetering();
        _addLiquidity(pool, 100 ether, 30 ether);
        _multipleSwap(pool, 10 ether, 5);
        _addLiquidity(pool, 200 ether, 60 ether);
        _multipleSwap(pool, 50 ether, 5);
        _addLiquidity(pool, 100 ether, 30 ether);
        vm.resumeGasMetering();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                             Liquidity helper's                             */
    /* -------------------------------------------------------------------------- */

    function _addLiquidity(MonoPool pool, uint256 amountToken0, uint256 amountToken1) internal {
        // Deal to fake some eth also on each token's (in case they are native)
        vm.deal(address(token0), amountToken0);
        vm.deal(address(token1), amountToken1);

        // Mint some initial tokens to the liquidity provider
        token0.mint(liquidityProvider, amountToken0);
        token1.mint(liquidityProvider, amountToken1);

        // Authorise the pool to spend our tokens
        vm.startPrank(liquidityProvider);
        token0.approve(address(pool), amountToken0);
        token1.approve(address(pool), amountToken1);
        vm.stopPrank();

        // Build the program to execute
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init()
            .appendAddLiquidity(amountToken0, amountToken1)
            .appendReceiveAll(true)
            .appendReceiveAll(false)
            .done();

        // Execute it
        vm.prank(liquidityProvider);
        pool.execute(program);
    }

    /* -------------------------------------------------------------------------- */
    /*                                Swap helper's                               */
    /* -------------------------------------------------------------------------- */

    function _simulateSwapActivity(MonoPool pool, uint256 maxAmount) internal outOfGasScope {
        // Perform a few swap's from t0 -> t1 and t1 -> t0
        _multipleSwap(pool, maxAmount / 2, 10);

        // A few only from t1 -> t0
        _swap1to0(pool, maxAmount / 10);
        _swap1to0(pool, maxAmount / 5);
        _swap1to0(pool, maxAmount / 10);

        // Once again some multiple swap with a lowest ampltitude
        _multipleSwap(pool, maxAmount / 3, 10);
    }

    function _multipleSwap(MonoPool pool, uint256 swapAmount, uint256 swapCount) internal {
        token0.mint(swapUser, swapAmount);
        // for i swap count
        for (uint256 i = 0; i < swapCount; i++) {
            // Swap 0 to 1
            _swap0to1(pool, swapAmount);

            // Perform the swap back
            _swap1to0(pool, swapAmount);
        }
    }

    function _swap0to1(MonoPool pool, uint256 swapAmount) internal {
        // Mint token & approve transfer
        token0.mint(swapUser, swapAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), swapAmount);

        // Build the swap op
        bytes memory program = _buildSwapViaAll(true, swapAmount, swapUser);

        // Send it
        vm.prank(swapUser);
        pool.execute(program);
    }

    function _swap1to0(MonoPool pool, uint256 swapAmount) internal {
        // Mint token & approve transfer
        token1.mint(swapUser, swapAmount);
        vm.prank(swapUser);
        token1.approve(address(pool), swapAmount);

        // Build the swap op
        bytes memory program = _buildSwapViaAll(false, swapAmount, swapUser);

        // Send it
        vm.prank(swapUser);
        pool.execute(program);
    }

    function _swap0to1(MonoPool pool) internal {
        // Mint token & approve transfer
        uint256 swapAmount = token0.balanceOf(swapUser);
        vm.prank(swapUser);
        token0.approve(address(pool), swapAmount);

        // Build the swap op
        bytes memory program = _buildSwapViaAll(true, swapAmount, swapUser);

        // Send it
        vm.prank(swapUser);
        pool.execute(program);
    }

    function _swap1to0(MonoPool pool) internal {
        uint256 swapAmount = token1.balanceOf(swapUser);
        vm.prank(swapUser);
        token1.approve(address(pool), swapAmount);

        // Build the swap op
        bytes memory program = _buildSwapViaAll(false, swapAmount, swapUser);

        // Send it
        vm.prank(swapUser);
        pool.execute(program);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Some assertion helper's                          */
    /* -------------------------------------------------------------------------- */

    /// @dev Assert that the pool reserve is synced
    function _assertReserveSynced(MonoPool pool) internal outOfGasScope {
        (Token _token0, Token _token1) = pool.getTokens();
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        (uint256 pFees0, uint256 pFees1) = pool.getProtocolFees();
        (, uint256 poolReserve0, uint256 poolReserve1) = pool.getPoolState();

        // Assert the balance of the contract eq the reserve
        assertEq(_token0.balanceOf(address(pool)), reserve0);
        assertEq(_token1.balanceOf(address(pool)), reserve1);

        // Assert the pool state equal the contract reserve
        assertEq(poolReserve0, reserve0 - pFees0);
        assertEq(poolReserve1, reserve1 - pFees1);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Some logs helper's                             */
    /* -------------------------------------------------------------------------- */

    function _logPoolState(MonoPool pool) internal view {
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        (uint256 pFees0, uint256 pFees1) = pool.getProtocolFees();
        (uint256 totalLiq, uint256 poolReserve0, uint256 poolReserve1) = pool.getPoolState();

        console.log("- Pool");
        console.log("-- Total liq: %d", totalLiq);
        console.log("-- Reserve t0: %d", poolReserve0);
        console.log("-- Reserve t1: %d", poolReserve1);
        console.log("- Contract");
        console.log("-- Reserve t0: %d", reserve0);
        console.log("-- Reserve t1: %d", reserve1);
        console.log("- Protocol");
        console.log("-- Fees t0: %d", pFees0);
        console.log("-- Fees t1: %d", pFees1);
    }

    /* -------------------------------------------------------------------------- */
    /*                          Simple program builder's                          */
    /* -------------------------------------------------------------------------- */

    /// @dev Build a simple swap program
    function _buildSwapViaDirectReceive(
        bool isSwap0to1,
        uint256 swapAmount,
        address user
    )
        internal
        pure
        returns (bytes memory program)
    {
        // forgefmt: disable-next-item
        program = EncoderLib.init()
            .appendSwap(isSwap0to1, swapAmount)
            .appendReceive(isSwap0to1, swapAmount)
            .appendSendAll(!isSwap0to1, user)
            .done();
    }

    /// @dev Build a simple swap program
    function _buildSwapViaDirectReceiveAndSend(
        bool isSwap0to1,
        uint256 swapAmount,
        uint256 swapOutput,
        address user
    )
        internal
        pure
        returns (bytes memory program)
    {
        // forgefmt: disable-next-item
        program = EncoderLib.init()
            .appendSwap(isSwap0to1, swapAmount)
            .appendReceive(isSwap0to1, swapAmount)
            .appendSend(!isSwap0to1, user, swapOutput)
            .done();
    }

    /// @dev Build a simple swap program
    function _buildSwapViaAll(
        bool isSwap0to1,
        uint256 swapAmount,
        address user
    )
        internal
        pure
        returns (bytes memory program)
    {
        // forgefmt: disable-next-item
        program = EncoderLib.init()
            .appendSwap(isSwap0to1, swapAmount)
            .appendReceiveAll(isSwap0to1)
            .appendSendAll(!isSwap0to1, user)
            .done();
    }

    /// @dev Build a simple swap program with limits
    function _buildSwapViaAllAndSendLimits(
        bool isSwap0to1,
        uint256 swapAmount,
        address user,
        uint256 minAmount,
        uint256 maxAmount
    )
        internal
        pure
        returns (bytes memory program)
    {
        // forgefmt: disable-next-item
        program = EncoderLib.init()
            .appendSwap(isSwap0to1, swapAmount)
            .appendReceiveAll(isSwap0to1)
            .appendSendAllWithLimits(!isSwap0to1, user, minAmount, maxAmount)
            .done();
    }

    /* -------------------------------------------------------------------------- */
    /*                       Utils, to ease the test process                      */
    /* -------------------------------------------------------------------------- */

    function _newToken(string memory label) internal returns (MockERC20 newToken) {
        newToken = new MockERC20();
        vm.label(address(newToken), label);
    }

    function _newUser(string memory label) internal returns (address addr) {
        addr = address(bytes20(keccak256(abi.encode(label))));
        vm.label(addr, label);
    }

    function _newUserWithPrivKey(string memory label) internal returns (address addr, uint256 privKey) {
        privKey = uint256(keccak256(abi.encode(label)));
        addr = vm.addr(privKey);
        vm.label(addr, label);
    }
}

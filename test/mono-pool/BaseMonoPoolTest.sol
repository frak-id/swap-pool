// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { EncoderLib } from "src/encoder/EncoderLib.sol";
import { MonoPool } from "src/MonoPool.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { MockWrappedNativeERC20 } from "test/mock/MockWrappedNativeERC20.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @dev Generic contract to test ono pool, providing some helpers
/// @author KONFeature <https://github.com/KONFeature>
abstract contract BaseMonoPoolTest is Test {
    using SafeTransferLib for address;
    using EncoderLib for bytes;

    /// @dev A few tokens to use for pool construction
    MockERC20 internal token0;
    MockERC20 internal token1;

    /// @dev Wrapped native token
    MockWrappedNativeERC20 internal wToken0;
    MockWrappedNativeERC20 internal wToken1;

    /// @dev Our liquidity provider user
    address internal liquidityProvider;

    /// @dev The fee receiver
    address internal feeReceiver;

    /// @dev The swap user
    address internal swapUser;
    uint256 internal swapUserPrivKey;

    /// @dev base bps to use (5%)
    uint256 internal bps = 50;

    /// @dev the base protocol fees (0.2%)
    uint16 internal protocolFee = 20;

    /// @dev Init some var for the base mono pool test
    function _initBaseMonoPoolTest() internal {
        // Create our users
        liquidityProvider = _newUser("liquidityProvider");
        feeReceiver = _newUser("feeReceiver");
        (swapUser, swapUserPrivKey) = _newUserWithPrivKey("swapUser");

        // Create a few tokens
        token0 = _newToken("token0");
        token1 = _newToken("token1");

        wToken0 = _newWrappedNativeToken("wToken0");
        wToken1 = _newWrappedNativeToken("wToken1");
    }

    /// @dev Disable pool fees
    function _disableProtocolFees(MonoPool pool) internal {
        vm.prank(feeReceiver);
        pool.updateFeeReceiver(address(0), 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                 Some modifier's to get specific pool states                */
    /* -------------------------------------------------------------------------- */

    modifier withLiquidity(MonoPool pool, uint256 amount0, uint256 amount1) {
        _addLiquidity(pool, amount0, amount1);
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
        bytes memory program = EncoderLib.init(3)
            .appendAddLiquidity(liquidityProvider, amountToken0, amountToken1)
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

    function _swap0to1(MonoPool pool, uint256 swapAmount) internal {
        // Mint token & approve transfer
        token0.mint(swapUser, swapAmount);
        vm.prank(swapUser);
        token0.approve(address(pool), swapAmount);

        // Build the swap op
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(4)
            .appendSwap(true, swapAmount)
            .appendReceiveAll(true)
            .appendSendAll(false, swapUser, false)
            .done();

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
        // forgefmt: disable-next-item
        bytes memory program = EncoderLib.init(4)
            .appendSwap(false, swapAmount)
            .appendReceiveAll(false)
            .appendSendAll(true, swapUser, false)
            .done();

        // Send it
        vm.prank(swapUser);
        pool.execute(program);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Some assertion helper's                          */
    /* -------------------------------------------------------------------------- */

    /// @dev Assert that the pool reserve is synced
    function _assertReserveSynced(MonoPool pool) internal {
        (address _token0, address _token1) = pool.getTokens();
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        (, uint256 poolReserve0, uint256 poolReserve1) = pool.getPoolState();

        // Assert the balance of the contract eq the reserve
        assertEq(_token0.balanceOf(address(pool)), reserve0);
        assertEq(_token1.balanceOf(address(pool)), reserve1);

        // Assert the pool state equal the contract reserve
        assertEq(poolReserve0, reserve0);
        assertEq(poolReserve1, reserve1);
    }

    /* -------------------------------------------------------------------------- */
    /*                       Utils, to ease the test process                      */
    /* -------------------------------------------------------------------------- */

    function _newToken(string memory label) internal returns (MockERC20 newToken) {
        newToken = new MockERC20();
        vm.label(address(newToken), label);
    }

    function _newWrappedNativeToken(string memory label) internal returns (MockWrappedNativeERC20 newToken) {
        newToken = new MockWrappedNativeERC20();
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

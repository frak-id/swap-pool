// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { EncoderLib } from "src/encoder/EncoderLib.sol";
import { MonoPool } from "src/MonoPool.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { BaseMonoPoolTest } from "./BaseMonoPoolTest.sol";

/// @dev Generic contract to test swap via permit
/// @author KONFeature <https://github.com/KONFeature>
contract MonoPoolSwapViaPermitTest is BaseMonoPoolTest {
    using EncoderLib for bytes;

    /// @dev The pool we will test
    MonoPool private pool;

    /// @dev The permit typehash
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        _initBaseMonoPoolTest();

        // Build our pool
        pool = new MonoPool(address(token0), address(token1), bps, feeReceiver, protocolFee);

        // Disable protocol fees on it
        _disableProtocolFees(pool);
    }

    /// @dev Test swapping token 0 to token 1
    function test_swap0to1_ok() public withLiquidity(pool, 100 ether, 100 ether) {
        uint256 swapAmount = 1 ether;
        token0.mint(swapUser, swapAmount);

        // forgefmt: disable-next-item
        bytes memory program = _initSwapAndPermitProgram(swapAmount)
            .appendReceiveAll(true)
            .appendSendAll(false, swapUser)
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

    /// @dev Generate the permit program
    function _initSwapAndPermitProgram(uint256 swapAmount) internal view returns (bytes memory program) {
        // Generate the permit signature

        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            swapUserPrivKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token0.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            _PERMIT_TYPEHASH, swapUser, address(pool), swapAmount, token0.nonces(swapUser), deadline
                        )
                    )
                )
            )
        );

        // Build the permit and swap op
        // forgefmt: disable-next-item
        {
        program = EncoderLib.init()
                .appendSwap(true, swapAmount)
                .appendPermitViaSig(true, swapAmount, deadline, v, r, s);
        }
    }
}

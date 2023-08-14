// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { EncoderLib } from "src/encoder/EncoderLib.sol";
import { MonoPool } from "src/MonoPool.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { BaseMonoPoolTest } from "./BaseMonoPoolTest.sol";

/// @dev Generic contract to test execution on the mono pool
/// @author KONFeature <https://github.com/KONFeature>
contract MonoPoolExecuteTest is BaseMonoPoolTest {
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

    /// @dev Test all the invalid constructor combinaison
    function test_constructor_ko() public {
        MonoPool constructTest;

        // Case token0 == addr0
        vm.expectRevert();
        constructTest = new MonoPool(address(0), address(2), bps, feeReceiver, protocolFee);

        // Case token1 == addr1
        vm.expectRevert();
        constructTest = new MonoPool(address(1), address(0), bps, feeReceiver, protocolFee);

        // Case BPS > Max BPS
        vm.expectRevert();
        constructTest = new MonoPool(address(1), address(2), 10_000, feeReceiver, protocolFee);

        // Case fee receiver == 0 & pFee > 0
        vm.expectRevert();
        constructTest = new MonoPool(address(1), address(2), bps, address(0), protocolFee);
    }

    /// @dev Test invalid executor operation
    function test_execute_ko_InvalidOp() public withLiquidity(pool, 100 ether, 100 ether) {
        // Build a random program
        bytes memory program = EncoderLib.init(3);

        uint256 op = 0xFF;
        assembly {
            let length := mload(program)
            mstore(program, add(program, 1))
            let initialOffset := add(add(program, 0x20), length)
            mstore(initialOffset, shl(248, op))
        }

        program.done();

        // Try to execute it
        // TODO: More precise revert with InvalidOp.selector, but how to passe the OP arguments?
        vm.expectRevert();
        pool.execute(program);
    }
}

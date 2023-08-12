// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

/// @title DecoderLib
/// @notice A library for decoding data inside a programm
/// @author philogy <https://github.com/philogy>
/// @author KONFeature <https://github.com/KONFeature>
/// @author Inspired by (https://github.com/Philogy/singleton-swapper/blob/main/src/MegaPool.sol) by Philogy
library DecoderLib {
    /// @dev Reads a string from an encoded program: `self`
    function readAddress(uint256 self) internal pure returns (uint256 newPtr, address addr) {
        uint256 rawVal;
        (newPtr, rawVal) = readUint(self, 20);
        addr = address(uint160(rawVal));
    }

    /// @dev Reads an uint from an encoded program, `self`, encoded on `size` bytes
    function readUint(uint256 self, uint256 size) internal pure returns (uint256 newPtr, uint256 x) {
        require(size >= 1 && size <= 32);
        assembly ("memory-safe") {
            newPtr := add(self, size)
            x := shr(shl(3, sub(32, size)), calldataload(self))
        }
    }

    /// @dev Reads an uint from an encoded program, `self`, encoded on 32 bytes
    function readFullUint(uint256 self) internal pure returns (uint256 newPtr, uint256 x) {
        assembly ("memory-safe") {
            newPtr := add(self, 32)
            x := calldataload(self)
        }
    }

    /// @dev Reads a bytes from an encoded program, `self`, encoded on `size` bytes
    function readBytes(uint256 self, uint256 size) internal pure returns (uint256 newPtr, bytes32 x) {
        require(size >= 1 && size <= 32);
        assembly ("memory-safe") {
            newPtr := add(self, size)
            x := shr(shl(3, sub(32, size)), calldataload(self))
        }
    }

    /// @dev Reads a bytes from an encoded program: `self`, encoded on 32 bytes
    function readFullBytes(uint256 self) internal pure returns (uint256 newPtr, bytes32 x) {
        assembly ("memory-safe") {
            newPtr := add(self, 32)
            x := calldataload(self)
        }
    }
}

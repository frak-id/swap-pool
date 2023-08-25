// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

/// @title DecoderLib
/// @notice A library for decoding data inside a programm
/// @author KONFeature <https://github.com/KONFeature>
/// @author Inspired by (https://github.com/Philogy/singleton-swapper/blob/main/src/MegaPool.sol) by Philogy
library DecoderLib {
    /// @dev Reads an address from an encoded program: `self`
    function readAddress(uint256 self) internal pure returns (uint256 newPtr, address addr) {
        assembly ("memory-safe") {
            newPtr := add(self, 20)
            addr := shr(96, calldataload(self))
        }
    }

    /// @dev Reads a boolean from an encoded program: `self`
    /// @dev Warning, the output boolean will be false if 0, or true if > 1 (encoded on 0xF)
    function readBool(uint256 self) internal pure returns (uint256 newPtr, bool boolean) {
        assembly ("memory-safe") {
            newPtr := add(self, 1)
            boolean := shr(248, calldataload(self))
        }
    }

    /// @dev Reads an uint from an encoded program, `self`, encoded on 1 bytes
    function readUint8(uint256 self) internal pure returns (uint256 newPtr, uint256 x) {
        assembly ("memory-safe") {
            newPtr := add(self, 1)
            x := shr(248, calldataload(self))
        }
    }

    /// @dev Reads an uint from an encoded program, `self`, encoded on 6 bytes
    function readUint48(uint256 self) internal pure returns (uint256 newPtr, uint256 x) {
        assembly ("memory-safe") {
            newPtr := add(self, 6)
            x := shr(208, calldataload(self))
        }
    }

    /// @dev Reads an uint from an encoded program, `self`, encoded on 16 bytes
    function readUint128(uint256 self) internal pure returns (uint256 newPtr, uint256 x) {
        assembly ("memory-safe") {
            newPtr := add(self, 16)
            x := shr(128, calldataload(self))
        }
    }

    /// @dev Reads an uint from an encoded program, `self`, encoded on 32 bytes
    function readUint256(uint256 self) internal pure returns (uint256 newPtr, uint256 x) {
        assembly ("memory-safe") {
            newPtr := add(self, 32)
            x := calldataload(self)
        }
    }

    /// @dev Reads a bytes from an encoded program: `self`, encoded on 32 bytes
    function readBytes32(uint256 self) internal pure returns (uint256 newPtr, bytes32 x) {
        assembly ("memory-safe") {
            newPtr := add(self, 32)
            x := calldataload(self)
        }
    }
}

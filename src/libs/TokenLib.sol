// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";

/// @dev Type to manage swappable token, with ease of ease for native token
type Token is address;

/// @dev Tell to use the lib below for every Token instance
using TokenLib for Token global;

/// @dev Tell to use the equals functions for the equals operator
using { unsafeEquals as == } for Token global;

/// @notice Check if a token equals another
/// @dev Mark it as unsafe since we don't have any upper byte cleaning, so address 0x00000000000011111111111111111111
/// will not be considered equals to 0xdead0000000011111111111111111111, even if they are the same if we were to used
/// address(...) == address(...)
function unsafeEquals(Token self, Token other) pure returns (bool isEquals) {
    assembly {
        isEquals := eq(self, other)
    }
}

/// @title TokenLib
/// @notice A library for managing a token in the swap pool.
/// @dev This lib can also handle native token
/// @dev A native token is represented by the address(0)
/// @author KONFeature <https://github.com/KONFeature>
library TokenLib {
    using SafeTransferLib for address;

    /// @dev Error throwned when the token is the native token and we try to perform a permit operation
    error PermitOnNativeToken();

    /// @dev 'bytes4(keccak256("PermitOnNativeToken()"))'
    uint256 private constant _PERMIT_ON_NATIVE_TOKEN_SELECTOR = 0x5d478b89;

    /// @notice Check if the current token is a representation of the native token
    function isNative(Token self) internal pure returns (bool isSelfNative) {
        assembly {
            isSelfNative := iszero(self)
        }
    }

    /// @notice Transfer `amount` of `token` to `to`.
    function transfer(Token self, address to, uint256 amount) internal {
        if (self.isNative()) {
            // Perform a native transfer of the amount
            to.safeTransferETH(amount);
        } else {
            // Perform the transfer of the token
            Token.unwrap(self).safeTransfer(to, amount);
        }
    }

    /// @notice Transfer `amount` of `token` to `to` from `msg.sender`.
    function transferFromSender(Token self, address to, uint256 amount) internal {
        // If we are in the case of a native token, nothing to do
        if (self.isNative()) return;

        // Try to perform the transfer
        Token.unwrap(self).safeTransferFrom(msg.sender, to, amount);
    }

    /// @notice Get the current balance of the caller
    function selfBalance(Token self) internal view returns (uint256 amount) {
        assembly {
            switch self
            case 0 {
                // Get the self balance directly in case of native token
                amount := selfbalance()
            }
            default {
                // Otherwise, get balance from the token
                // from:
                // https://github.com/Vectorized/solady/blob/9ea395bd66b796c7f08afd18a565eea021c98127/src/utils/SafeTransferLib.sol#L366
                mstore(0x14, address()) // Store the `account` argument.
                mstore(0x00, 0x70a08231000000000000000000000000) // `balanceOf(address)`.
                amount :=
                    mul(
                        mload(0x20),
                        and( // The arguments of `and` are evaluated from right to left.
                            gt(returndatasize(), 0x1f), // At least 32 bytes returned.
                            staticcall(gas(), self, 0x10, 0x24, 0x20, 0x20)
                        )
                    )
            }
        }
    }

    /// @notice Get the current balance of `owner`
    function balanceOf(Token self, address owner) internal view returns (uint256 amount) {
        assembly {
            switch self
            case 0 {
                // Get the native balance of the owner in case of native token
                amount := balance(owner)
            }
            default {
                // Otherwise, get balance from the token
                // From:
                // https://github.com/Vectorized/solady/blob/9ea395bd66b796c7f08afd18a565eea021c98127/src/utils/SafeTransferLib.sol#L366
                mstore(0x14, owner) // Store the `account` argument.
                mstore(0x00, 0x70a08231000000000000000000000000) // `balanceOf(address)`.
                amount :=
                    mul(
                        mload(0x20),
                        and( // The arguments of `and` are evaluated from right to left.
                            gt(returndatasize(), 0x1f), // At least 32 bytes returned.
                            staticcall(gas(), self, 0x10, 0x24, 0x20, 0x20)
                        )
                    )
            }
        }
    }

    /// @notice Perform the permit op on the given token
    function permit(
        Token self,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        internal
    {
        // Permit is not supported on native token
        assembly {
            if iszero(self) {
                mstore(0x00, _PERMIT_ON_NATIVE_TOKEN_SELECTOR)
                revert(0x1c, 0x04)
            }
        }

        // Perform the permit operation
        // Disable Slither warning about the loop, cause in case of a pool with 2
        // erc20 implementing eip2612, a user can decide to use a signature approval when adding liquidity to both
        // tokens
        // slither-disable-next-line calls-loop
        ERC20(Token.unwrap(self)).permit(owner, spender, value, deadline, v, r, s);
    }
}

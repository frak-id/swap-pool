// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ERC20 } from "solady/tokens/ERC20.sol";

/// @author KONFeature <https://github.com/KONFeature>
contract MockERC20 is ERC20 {
    function name() public pure virtual override returns (string memory) {
        return "Mock Token";
    }

    function symbol() public pure virtual override returns (string memory) {
        return "MCK";
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        _burn(to, amount);
    }
}

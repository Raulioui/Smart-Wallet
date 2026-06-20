// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

// Simulates a DEX swap at a fixed 1:2 rate (1 tokenIn = 2 tokenOut).
// Used in unit tests to avoid depending on Uniswap or any real DEX.
contract MockSwapRouter {
    error MockSwapRouter__SlippageExceeded();

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        amountOut = amountIn * 2;
        if (amountOut < minAmountOut) revert MockSwapRouter__SlippageExceeded();

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(tokenOut).mint(msg.sender, amountOut);
    }
}

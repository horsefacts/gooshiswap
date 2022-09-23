// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract Gooshi is ERC20("Gooshi", "GOOSHI", 18) {
    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the Gooshiswap contract.
    address public immutable gooshiSwap;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the addresses of relevant contracts.
    /// @param _gooshiSwap Address of the GooshiSwap contract.
    constructor(address _gooshiSwap) {
        gooshiSwap = _gooshiSwap;
    }

    /*//////////////////////////////////////////////////////////////
                             MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Requires caller address to match user address.
    modifier only(address user) {
        if (msg.sender != user) revert Unauthorized();

        _;
    }

    /// @notice Mint any amount of gooshi to a user. Can only be called by GooshiSwap.
    /// @param to The address of the user to mint gooshi to.
    /// @param amount The amount of gooshi to mint.
    function mintForGooshiSwap(address to, uint256 amount) external only(gooshiSwap) {
        _mint(to, amount);
    }

    /// @notice Burn any amount of gooshi from a user. Can only be called by GooshiSwap.
    /// @param from The address of the user to burn gooshi from.
    /// @param amount The amount of gooshi to burn.
    function burnForGooshiSwap(address from, uint256 amount) external only(gooshiSwap) {
        _burn(from, amount);
    }
}

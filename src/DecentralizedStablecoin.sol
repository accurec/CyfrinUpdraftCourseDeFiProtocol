// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStablecoin
 * @author Zhernovkov Maxim
 * Collateral: Exogenous (ETH & BTC).
 * Minting: Algorithmic.
 * Relative stability: Pegged to USD.
 * This contract is meant to be governed by DSCEngine. This cntract is just the ERC20 implementation of our stablecoin system.
 */
contract DecentralizedStablecoin is ERC20Burnable, Ownable {
    error DecentralizedStablecoin__MustBeMoreThanZero();
    error DecentralizedStablecoin__BurnAmountMoreThanBalance();
    error DecentralizedStablecoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStablecoin", "DSC") Ownable(msg.sender) {} // Need to make sure to transfer ownership in deployment

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralizedStablecoin__MustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert DecentralizedStablecoin__BurnAmountMoreThanBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStablecoin__NotZeroAddress();
        }

        if (_amount <= 0) {
            revert DecentralizedStablecoin__MustBeMoreThanZero();
        }

        _mint(_to, _amount);

        return true;
    }
}

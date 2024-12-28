// Handler is going to narrow down the way we call functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStablecoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator public ethPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // uint96 here so that we can deposit this initially and then later deposit more to not overflow uint256

    constructor(DSCEngine _dscEngine, DecentralizedStablecoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
    }

    // This test would uncover a system vulnerability that if collateral price drops quickly in a single block, then
    // our system would break and protocol would be worthless. Because theoretically collateral value could go so low
    // that liquidations would not help and not work
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethPriceFeed.updateAnswer(newPriceInt);
    // }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // TODO: I am not sure if we need to keep track of depositors here and in redeemCollateral function, because
    // fro the test runs that I've done I've not seen different addresses calling these functions in fuzz tests
    function mintDsc(uint256 amount) public {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(msg.sender);
        int256 maxDscToMint = int256(collateralValueInUsd) / 2 - int256(totalDscMinted);

        if (maxDscToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxDscToMint));

        if (amount == 0) {
            return;
        }

        vm.prank(msg.sender);
        dsce.mintDsc(amount);
    }


    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(msg.sender);
        int256 totalAllowedUsdToRedeem = int256(collateralValueInUsd) - int256(totalDscMinted) * 2;

        if (totalAllowedUsdToRedeem < 0) {
            return;
        }

        // Need to make sure we only redeem what we can to not ruin the health factor
        uint256 potentialCollateralToRedeem = dsce.getTokenAmountFromUsd(address(collateral), uint256(totalAllowedUsdToRedeem));
        uint256 userCollateralDeposited = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));
        uint256 maxCollateralToRedeem = Math.min(potentialCollateralToRedeem, userCollateralDeposited);

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        // Note: could also make use of vm.assume here to skip the fuzz and start new one if amount collateral is 0 and min was 1
        if (amountCollateral == 0) {
            return; // Return here, because otherwise we would revert in DSCEngine if redeeming 0 collateral
        }

        vm.prank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    ///////////////////////////////////////
    // Helper Functions
    ///////////////////////////////////////

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}

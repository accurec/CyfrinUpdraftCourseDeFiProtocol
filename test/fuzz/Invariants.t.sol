// Have our invariant aka properties that system holds true for all time
// What are our invariants?
// 1. Total supply of DSC should be less than the total value of collateral
// 2. Getter view functons should never revert <- evergreen invariant

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DecentralizedStablecoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler)); // <- call functions here instead of "address(dsce)"
            // targetContract(address(dsce));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // Get the value of all the collateral in the protocol
        // Compare it to all the debt (DSC)

        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total supply: ", totalSupply);

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        dsce.getPrecision();
        dsce.getLiquidationBonus();
        dsce.getAdditionalFeedPrecision();
        dsce.getLiquidationPrecision();
        dsce.getCollateralTokens();

        // TODO: Not sure if these below can be tested as part of fuzzing
        // dsce.getAccountInformation(user);
        // dsce.getCollateralBalanceOfUser(user, token);
        // dsce.getAccountCollateralValue(user);
        // dsce.getUsdValue(token, tokenAmount);
        // calculateHealthFactor
        // getTokenAmountFromUsd
    }
}

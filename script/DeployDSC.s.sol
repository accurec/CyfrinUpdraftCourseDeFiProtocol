// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStablecoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, address deployerAccount) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerAccount);
        DecentralizedStablecoin dsc = new DecentralizedStablecoin();
        DSCEngine dsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(dsce));
        vm.stopBroadcast();

        console.log("Deployed wETH token: ", weth);
        console.log("Deployed wBTC token: ", wbtc);
        console.log("Deployed wETH price feed: ", wethUsdPriceFeed);
        console.log("Deployed wBTC price feed: ", wbtcUsdPriceFeed);
        console.log("Deployed DSC token: ", address(dsc));
        console.log("Deployed DSCEngine contract: ", address(dsce));

        return (dsc, dsce, config);
    }
}

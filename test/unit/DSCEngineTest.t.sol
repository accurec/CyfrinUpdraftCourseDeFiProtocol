// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStablecoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 20 ether;

    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant PRECISION = 1e18;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    // These are copied from the "DSCEngine.sol", because this is the only (?) way we can make it work with testing in Foundry
    event DSCEngine__CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DSCEngine__CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    // TODO: Fix so that tests work for Sepolia test chain
    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////////////////
    // Constructor tests
    //////////////////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedsAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////////////////////////////
    // Price tests
    //////////////////////////////////////////

    function testGetUsdValueReturnsCorrectValue() public view {
        uint256 wethAmount = 14 ether;
        (, int256 expectedPricePerEth,,,) = AggregatorV3Interface(ethUsdPriceFeed).latestRoundData();

        assertEq(
            uint256(expectedPricePerEth) * ADDITIONAL_FEED_PRECISION * wethAmount / PRECISION,
            dsce.getUsdValue(weth, wethAmount)
        );
    }

    function testTokenAmountFromUsd() public view {
        uint256 usdAmount = 5035;
        (, int256 expectedPricePerEth,,,) = AggregatorV3Interface(ethUsdPriceFeed).latestRoundData();

        assertEq(
            (usdAmount * PRECISION) / (uint256(expectedPricePerEth) * ADDITIONAL_FEED_PRECISION),
            dsce.getTokenAmountFromUsd(weth, usdAmount)
        );
    }

    //////////////////////////////////////////
    // Deposit collateral tests
    //////////////////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL); // Approve spending this much token from caller (user)
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZeroRequired.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfCollateralProvidedForUnknowToken() public {
        ERC20Mock unknownCollateralToken = new ERC20Mock();
        unknownCollateralToken.mint(user, STARTING_ERC20_BALANCE);

        vm.startPrank(user);
        unknownCollateralToken.approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dsce.depositCollateral(address(unknownCollateralToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralEmitsTheEvent() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL); // Approve spending this much token from caller (user)

        vm.expectEmit(true, true, true, false, address(dsce));
        emit DSCEngine__CollateralDeposited(user, weth, AMOUNT_COLLATERAL);

        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedTwoCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepoistCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);

        assertEq(0, totalDscMinted);
        assertEq(AMOUNT_COLLATERAL, dsce.getTokenAmountFromUsd(weth, collateralValueInUsd));
    }

    //////////////////////////////////////////
    // Mint DSC tests
    //////////////////////////////////////////

    function testMintDscRevertsIfZeroDscNeedsToBeMinted() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZeroRequired.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testCannotMintDscIfNoCollateralDeposited() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__DscAmountMintedMoreThanAllowedWithCollateral.selector, 0)
        );
        dsce.mintDsc(1 ether);
        vm.stopPrank();
    }

    function testCanMintDscIfCollateralIsDepositedAndHealthFactorIsGood() public depositedCollateral {
        vm.startPrank(user);
        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        dsce.mintDsc(collateralValueInUsd / 2);
        vm.stopPrank();
    }

    function testCanotMintDscIfCollateralIsDepositedAndHealthFactorIsNotGood() public depositedCollateral {
        vm.startPrank(user);
        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 dscToMint = collateralValueInUsd / 2 + 1 ether;
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(dscToMint, collateralValueInUsd);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__DscAmountMintedMoreThanAllowedWithCollateral.selector, expectedHealthFactor
            )
        );
        dsce.mintDsc(dscToMint);
        vm.stopPrank();
    }

    function testCanotMintDscIfTwoCollateralIsDepositedAndHealthFactorIsNotGood() public depositedTwoCollateral {
        vm.startPrank(user);
        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 dscToMint = collateralValueInUsd / 2 + 1 ether;
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(dscToMint, collateralValueInUsd);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__DscAmountMintedMoreThanAllowedWithCollateral.selector, expectedHealthFactor
            )
        );
        dsce.mintDsc(dscToMint);
        vm.stopPrank();
    }

    //////////////////////////////////////////
    // Liquidation tests
    //////////////////////////////////////////

    function testMustImproveHealthFactorOnLiquidation() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        int256 newEthPrice = 10e8; // 1 ETH = $10. Pretend like ETH has dropped in price so that user health factor would be low
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newEthPrice);
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        uint256 debtToCover = 18 ether; // With the price drop and the amount of DSC to cover here, the ending health factor will be actually lower than starting
        dsce.liquidate(weth, user, debtToCover);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsFine.selector);
        dsce.liquidate(weth, user, amountToMint);
        vm.stopPrank();
    }

    function testOnLiquidationCollateralRedeemedEventIsEmitted() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18. Pretend like ETH has dropped in price so that user health factor would be low

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);

        uint256 liquidatedAmountCollateral = 3_611_111_111_111_111_112;

        vm.expectEmit(true, true, true, false, address(dsce));
        emit DSCEngine__CollateralRedeemed(user, liquidator, weth, liquidatedAmountCollateral);

        dsce.liquidate(weth, user, amountToMint); // We are covering their whole debt
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18. Pretend like ETH has dropped in price so that user health factor would be low

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.liquidate(weth, user, amountToMint); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = dsce.getTokenAmountFromUsd(weth, amountToMint)
            + dsce.getTokenAmountFromUsd(weth, amountToMint) * dsce.getLiquidationBonus() / dsce.getLiquidationPrecision();

        uint256 hardCodedExpected = 6_388_888_888_888_888_888;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = dsce.getTokenAmountFromUsd(weth, amountToMint)
            + dsce.getTokenAmountFromUsd(weth, amountToMint) * dsce.getLiquidationBonus() / dsce.getLiquidationPrecision();
        uint256 usdAmountLiquidated = dsce.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = dsce.getUsdValue(weth, amountCollateral) - usdAmountLiquidated;

        (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 hardCodedExpectedValue = 65_000_000_000_000_000_016;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dsce.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, amountToMint); // DSC is taken from liquidator, but in the books they still owe to the protocol
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dsce.getAccountInformation(user);
        assertEq(userDscMinted, 0);
    }

    //////////////////////////////////////////
    // Deposit collateral and mint DSC tests
    //////////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = amountCollateral * uint256(price) * dsce.getAdditionalFeedPrecision() / dsce.getPrecision();
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(weth, amountCollateral));
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__DscAmountMintedMoreThanAllowedWithCollateral.selector, expectedHealthFactor
            )
        );
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    //////////////////////////////////////////
    // Burn DSC tests
    //////////////////////////////////////////

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZeroRequired.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(user);
        vm.expectRevert(); // Arithmetic underflow will be thrown
        dsce.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(dsce), amountToMint);
        dsce.burnDsc(amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }
}

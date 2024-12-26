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

import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Zhernovkov Maxim
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1.00 peg.
 * This stablecoin has the properties:
 * - Exogenous collateral
 * - Dollar pegged
 * - Algorithmically stable
 * It is similar to DAI is DAI had no governance, no fees, and was only backed by WETH and WBTC.
 * Our DSC system should always be overcollateralized. At no point should the value of all collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////////////
    // Errors
    ////////////////////////

    error DSCEngine__MoreThanZeroRequired();
    error DSCEngine__TokenAddressAndPriceFeedsAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__CollateralTransferFailed();
    error DSCEngine__DscAmountMintedMoreThanAllowedWithCollateral(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsFine();
    error DSCEngine__HealthFactorNotImproved();

    ////////////////////////
    // State Variables
    ////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100; // 200% overcollateralized
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 15; // This means 15% bonus

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;

    DecentralizedStablecoin private immutable i_dscAddress;
    address[] private s_collateralTokens;

    ////////////////////////
    // Events
    ////////////////////////

    event DSCEngine__CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DSCEngine__CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    ////////////////////////
    // Modifiers
    ////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MoreThanZeroRequired();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        // If the token is not allowed, then revert
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ////////////////////////
    // Functions
    ////////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD price feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedsAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dscAddress = DecentralizedStablecoin(dscAddress);
    }

    ////////////////////////
    // External Functions
    ////////////////////////

    /**
     * @notice This function will deposit your collateral and mint DSC as one transaction
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The token amount to deposit
     * @param amountDscToMint The amount of stablecoin to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI: checks, effects, interactions
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of the token to deposit as collateral
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit DSCEngine__CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert DSCEngine__CollateralTransferFailed();
        }
    }

    /**
     * @notice This function burns DSC and redeems collateral in one transaction
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDsc The amount of DSC to burn
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDsc)
        external
    {
        burnDsc(amountDsc);
        redeemCollateral(tokenCollateralAddress, amountCollateral); // This already checks health factor
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI. User must have more collateral value than minimum threshold
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;

        // If they minted $150 DSC but have only $100 cllateral, then revert
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dscAddress.mint(msg.sender, amountDscToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amountDsc) public moreThanZero(amountDsc) nonReentrant {
        _burnDsc(amountDsc, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    // Logic: if someone is almost undercollateralized, we will pay you to liquidate them!
    /**
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking user funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized for this protocol to work
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we would not be able to incentivise the liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated. Follows CEI
     * @param collateral The ERC20 collateral address to liquidate
     * @param userAddress The user that is going to be liquidated
     * @param debtToCover The amount of DSC to burn
     */
    function liquidate(address collateral, address userAddress, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(userAddress);

        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsFine();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        uint256 totalCollateral = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(collateral, totalCollateral, userAddress, msg.sender);
        _burnDsc(debtToCover, userAddress, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(userAddress);
 
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address userAddress) external view returns (uint256) {
        return _healthFactor(userAddress);
    }

    ///////////////////////////////////////
    // Private & Internal View Functions
    ///////////////////////////////////////

    /**
     * @dev Low-level internal function. Do not call unless the function calling it is checking for health factor
     * @param amountDsc Amount of DSC to burn
     * @param onBehalfOf On who's behalf the debt is being paid
     * @param dscFrom Who is the liquidator
     */
    function _burnDsc(uint256 amountDsc, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDsc;
        bool success = i_dscAddress.transferFrom(dscFrom, address(this), amountDsc);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dscAddress.burn(amountDsc);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        // Rely on Solidity compiler here to revert, in case of underflow
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit DSCEngine__CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _revertIfHealthFactorIsBroken(address userAddress) internal view {
        // 1. Check health factor (do they have enough collateral?)
        // 2. Revert, if factor is bad
        uint256 userHealthFactor = _healthFactor(userAddress);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__DscAmountMintedMoreThanAllowedWithCollateral(userHealthFactor);
        }
    }

    /**
     * @notice Returns how close to liquidation the user is. If a user goes below one, then they can get liquidated
     * @param userAddress user address to check health of
     */
    function _healthFactor(address userAddress) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(userAddress);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralTotalValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralTotalValueInUsd = getAccountCollateralValue(user);
    }

    ///////////////////////////////////////
    // Public & External View Functions
    ///////////////////////////////////////

    function getTokenAmountFromUsd(address collateralToken, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralToken]);
        (, int256 tokenPrice,,,) = priceFeed.latestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(tokenPrice) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // Loop through each collateral token and map to price to get USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];

            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        // Price feed stuff
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // 1 ETH = $1000
        // The returned value from CL will be 1000 * 1e8
        return uint256(price) * ADDITIONAL_FEED_PRECISION * amount / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }
}

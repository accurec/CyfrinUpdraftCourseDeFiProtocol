## About

This is a third project that I've done as part of my learning of smart contract development using Solidity and Foundry. This is a DeFi application for users to deposit collateral in the form of wETH and wBTC tokens, and then mint decentralized stablecoin DSC. The DSC is pegged to a value of $1 USD and the peg is supported by the 200% overcollaterilization in the system. The system is designed to incentivize liquidations of the user's collateral by external parties, if user's health factor is below a threshold. The liquidators incentives are extra collateral that the system will give to the liquidator, so that they are profitable.

![Protocol diagram](/resources/Protocol%20diagram.png)

## Using the repository

1) Run
```
git clone https://github.com/accurec/CyfrinUpdraftCourseDeFiProtocol.git
```
2) Run `make install` to install required dependencies.
3) Run `make build` to build the project.
4) Add `.env` file with the following variables: `SEPOLIA_RPC_URL` - could take this from Alchemy; `ETHERSCAN_API_KEY` - needed for automatic verification, can get it from Etherscan account. Make sure you also provide local account key using `cast wallet import` command. Then, in `env` file you can supply the key name under `LOCAL_ACCOUNT` variable. Also need to add `LOCAL_RPC_URL`, and `SEPOLIA_ACCOUNT_ADDRESS` for deployemtns to Sepolia, along with the `SEPOLIA_ACCOUNT` value similar to what we would import for `LOCAL_ACCOUNT`.
5) Run `make deploy-local` to deploy to local `anvil` network (don't forget to start it).
6) After deploying to local there will be output of deployed contracts in terminal log like this:
```
Deployed wETH token: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
Deployed wBTC token: 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
Deployed wETH price feed: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
Deployed wBTC price feed: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
Deployed DSC token: 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707
Deployed DSCEngine contract: 0x0165878A594ca255338adfa4d48449f69242Eb8F
```
7) After the contracts have been deployed, we can add more variables to `.env` file: 
   - `LOCAL_WETH_ADDRESS` - the wETH token deployed address.
   - `LOCAL_USER_ACCOUNT` - this would normally be a local user address provided by anvil, such as `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`. It would be an account that we stored the key for in the `LOCAL_ACCOUNT` variable.
   - `LOCAL_WETH_USER_AMOUNT` - this is an amount of wETH that we would want to mint for local user to then deposit as collateral.
   - `LOCAL_DSC_ENGINE_ADDRESS` - the DSCEngine deployed address.
   - `LOCAL_MINT_DSC_AMOUNT` - the amount of DSC we would want to mint for the user after they deposit the collateral.
   - `LOCAL_DSC_ADDRESS` - the DSC stablecoin address.
   - `LOCAL_WETH_PRICE_FEED_ADDRESS` - this is the address of a wETH price feed.
8) We can then interact with these contracts to get some initial data, to make sure that they are correctly setup. For example: `make get-local-weth-latest-price`, then get the second parameter value from the output and convert it to `dec` value like this: `cast --to-base VALUE dec`. The response should be `200000000000`.
9) We can then start using the protocol by calling `make` commands in order:
   - `make mint-weth-for-local-user` - will mint some wETH for local user to use as collateral.
   - `make local-user-approve-weth-spend` - will approve spending wETH for DSCEngine contract.
   - `make local-user-deposit-weth-collateral-and-mint-dsc` - will deposit wETH as collateral and mint DSC (assumint DSC amount to mint was not too big, otherwise the transaction will fail).
   - `make get-dsc-balance-for-local-user` - check DSC balance for local user.
   - `make get-local-user-health-factor` - get health factor for local user.

NOTE: I have not used/deployed this on Sepolia testnet, since I do not have enough test tokens there at the moment.

## Notes

1) One of the protocol's weak points is that if `wETH` and/or `wBTC` prices plummet, then the system will not be able to incentivize liquidations and DSC stablecoin backing will be rendered insolvant.
2) ChainLink network can become stale/blow up. I'm using the `OracleLib` library to make sure that if the price feeds are stale, then the protocol stops execution and liquidations/minting of DSC are reverted.

## Learnings and techniques used

As part of lesson I've learned a bunch of things:
1) Using Openzeppelin `ERC20Burnable`, `Ownable` contracts to create DSC stablecoin contract.
2) Using library to wrap ChainLink oracle get price functionality and revert, if the feed is stale.
3) Fuzz testing. Invariants and handlers.
4) Re-entrancy vulnerability concept and how we can protect against it.
5) Better understanding of how to do proper math in Solidity.
6) Concepts of how to use collateral, mint stablecoins, and support health factor so that stablecoin stays backed by the collateral. Concept of liquidations and incentives.
7) Concepts behind `abi.encodePacked`, function call encoding including parameters. How to verify the call in the web3 wallets, such as Metamask.

## Useful resources

1) [Simple Security Toolkit](https://github.com/nascentxyz/simple-security-toolkit/tree/main)
2) [Ethereum Unit Converter](https://eth-converter.com/)
3) [Re-Entrancy Vulnerability Overview](https://owasp.org/www-project-smart-contract-top-10/2023/en/src/SC01-reentrancy-attacks.html#:~:text=A%20reentrancy%20attack%20exploits%20the,withdrawals%2C%20using%20the%20same%20state.)
4) [Foundry Fuzz Testing](https://book.getfoundry.sh/forge/fuzz-testing)

## TODO list

1) Fix tests so that they are passing on Sepolia testnet.
2) Add integrations tests.
3) Fix `invariant_gettersShouldNotRevert` invariant so that all getters can be fuzz tested. Most likely need to add the logic to handler.
4) Deploy and test on Sepolia testnet. Add `Makefile` commands to deploy to Sepolia.
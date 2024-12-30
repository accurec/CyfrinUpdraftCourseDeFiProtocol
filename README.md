## About

This is a third project that I've done as part of my learning of smart contract development using Solidity and Foundry. This is a DeFi application for users to deposit collateral in the form of wETH and wBTC tokens, and then mint decentralized stablecoin DSC. The DSC is pegged to a value of $1 USD and the peg is supported by the 200% overcollaterilization in the system. The system is designed to incentivize liquidations of the user's collateral by external parties, if user's health factor is below a threshold. The liquidators incentives are extra collateral that the system will give to the liquidator, so that they are profitable.

![Protocol diagram](/resources/Protocol%20diagram.png)

## Using the repository



## Notes



## Learnings and techniques used

As part of lesson I've learned a bunch of things:


## Useful resources

1) [Simple Security Toolkit](https://github.com/nascentxyz/simple-security-toolkit/tree/main)
2) [Ethereum Unit Converter](https://eth-converter.com/)
3) [Reentrancy Vulnerability Overview](https://owasp.org/www-project-smart-contract-top-10/2023/en/src/SC01-reentrancy-attacks.html#:~:text=A%20reentrancy%20attack%20exploits%20the,withdrawals%2C%20using%20the%20same%20state.)
4) []()

## TODO list



1. (Relative stability) Anchored or Pegged -> $1.00
   1. Chainlink price feed
   2. Set a function to exchange ETH & BTC -> $$$
2. Stability mechanism (minting): algorithmic (decentralized)
   1. People can only mint stablecoin with enough collateral (coded)
3. Collateral: exogenous (crypto)
    1 .wETH
    1. wBTC
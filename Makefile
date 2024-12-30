-include .env

.PHONY: all test deploy

build:
	forge build

test:
	forge test

install:
	forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit
	forge install foundry-rs/forge-std@v1.8.2 --no-commit
	forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-commit

deploy-local:
	@forge script script/DeployDSC.s.sol:DeployDSC --rpc-url $(LOCAL_RPC_URL) --account defaultKey --broadcast -vv

get-local-weth-latest-price:
	@cast call $(LOCAL_WETH_PRICE_FEED_ADDRESS) "latestRoundData()"

mint-weth-for-local-user:
	@cast send $(LOCAL_WETH_ADDRESS) "mint(address, uint256)" $(LOCAL_USER_ACCOUNT) $(LOCAL_WETH_USER_AMOUNT) --account $(LOCAL_ACCOUNT)

get-weth-balance-for-local-user:
	@cast call $(LOCAL_WETH_ADDRESS) "balanceOf(address)" $(LOCAL_USER_ACCOUNT)

get-weth-balance-for-local-dscengine:
	@cast call $(LOCAL_WETH_ADDRESS) "balanceOf(address)" $(LOCAL_DSC_ENGINE_ADDRESS)

local-user-approve-weth-spend:
	@cast send $(LOCAL_WETH_ADDRESS) "approve(address,uint256)" $(LOCAL_DSC_ENGINE_ADDRESS) $(LOCAL_WETH_USER_AMOUNT) --from $(LOCAL_USER_ACCOUNT) --account $(LOCAL_ACCOUNT)

local-user-deposit-weth-collateral-and-mint-dsc:
	@cast send $(LOCAL_DSC_ENGINE_ADDRESS) "depositCollateralAndMintDsc(address, uint256, uint256)" $(LOCAL_WETH_ADDRESS) $(LOCAL_WETH_USER_AMOUNT) $(LOCAL_MINT_DSC_AMOUNT) --account $(LOCAL_ACCOUNT)

get-dsc-balance-for-local-user:
	@cast call $(LOCAL_DSC_ADDRESS) "balanceOf(address)" $(LOCAL_USER_ACCOUNT)

get-local-user-health-factor:
	@cast call $(LOCAL_DSC_ENGINE_ADDRESS) "getHealthFactor(address)" $(LOCAL_USER_ACCOUNT)
const fs = require('fs');
const ethJsUtil = require('ethereumjs-util');

const BalleRewardedVaultV1 = artifacts.require('BalleRewardedVaultV1');
const CakeLPStrategyV1 = artifacts.require('CakeLPStrategyV1');

module.exports = async function (deployer, network, accounts) {
  // Load network config data
  const networkConfigFilename = `.env.${network}.json`;
  const networkConfig = JSON.parse(fs.readFileSync(networkConfigFilename));

  // Get addresses
  const pancakePairAddress = networkConfig.PancakePairAddress;
  const pancakeRouterAddress = networkConfig.PancakeRouterAddress;
  const masterchefAddress = networkConfig.MasterchefAddress;
  const vaultRewardPoolAddress = networkConfig.vaultRewardPoolAddress;
  const treasuryAddress = networkConfig.treasuryAddress;
  const rewardPoolAddress = networkConfig.rewardPoolAddress;
  const balle = networkConfig.BALLE;
  const wbnb = networkConfig.WBNB;
  const cake = networkConfig.CAKE;

  if (network == 'bsc_mainnet') {
  } else {
    let nonce = await web3.eth.getTransactionCount(accounts[0])
    console.log('NONCE: ', nonce)
    let strategyAddress = ethJsUtil.bufferToHex(ethJsUtil.generateAddress(accounts[0], nonce + 1));
    console.log('ADDRESS: ', strategyAddress)

    let ballePancakeBALBT_BNB = await deployer.new(BalleRewardedVaultV1, 
      pancakePairAddress, strategyAddress, 
      'Balle Pancake bALBT-BNB', 'ballePancakeBALBT-BNB', 60,
      balle, vaultRewardPoolAddress, 100
    );
    console.log(ballePancakeBALBT_BNB === undefined ? 'UNDEFINED!!??' : 'OK');

    networkConfig['ballePancakeBALBT_BNB'] = ballePancakeBALBT_BNB.address;

    let stratPancakeBALBT_BNB = await deployer.new(CakeLPStrategyV1,
      wbnb, balle, cake, pancakeRouterAddress, masterchefAddress,
      pancakePairAddress, 103, rewardPoolAddress, treasuryAddress,
      ballePancakeBALBT_BNB.address
    );
    console.log(ballePancakeBALBT_BNB === undefined ? 'UNDEFINED!!??' : 'OK');
    console.log('STRAT. ADDRESS: ', stratPancakeBALBT_BNB.address)

    networkConfig['stratPancakeBALBT_BNB'] = stratPancakeBALBT_BNB.address;
    fs.writeFileSync(networkConfigFilename, JSON.stringify(networkConfig, null, 2), { flag: 'w' });
  }

};

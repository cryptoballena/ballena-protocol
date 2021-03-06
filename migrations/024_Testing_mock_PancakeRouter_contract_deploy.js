const fs = require('fs');

const PancakeRouter = artifacts.require('PancakeRouter');

module.exports = async function (deployer, network, accounts) {

  if (network != 'develop') {
    // Load network config data
    const networkConfigFilename = `.env.${network}.json`;
    const networkConfig = JSON.parse(fs.readFileSync(networkConfigFilename));
    let txRegistry = networkConfig.txRegistry;

    if (network != 'bsc_mainnet') {
      const pancakePairAddress = networkConfig.pancakePairAddress;

      await deployer.deploy(PancakeRouter, pancakePairAddress);
      txRegistry.push(PancakeRouter.transactionHash);

      networkConfig['txRegistry'] = txRegistry;
      networkConfig['pancakeRouterAddress'] = PancakeRouter.address;

      fs.writeFileSync(networkConfigFilename, JSON.stringify(networkConfig, null, 2), { flag: 'w' });
    } 
  }
  
};

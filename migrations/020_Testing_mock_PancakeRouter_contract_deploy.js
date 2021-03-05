const fs = require('fs');

const PancakeRouter = artifacts.require('PancakeRouter');

module.exports = async function (deployer, network, accounts) {
  // Load network config data
  const networkConfigFilename = `.env.${network}.json`;
  const networkConfig = JSON.parse(fs.readFileSync(networkConfigFilename));

  if (network != 'bsc_mainnet') {
    const pancakePairAddress = networkConfig.PancakePairAddress;

    await deployer.deploy(PancakeRouter, pancakePairAddress);

    networkConfig['PancakeRouterAddress'] = PancakeRouter.address;

    fs.writeFileSync(networkConfigFilename, JSON.stringify(networkConfig, null, 2), { flag: 'w' });
  } 

};

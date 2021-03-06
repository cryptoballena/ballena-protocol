// contracts/mocks/RewardedVaultMock1.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.7.4;

import "../interfaces/IVaultRewardPool.sol";

contract RewardedVaultMock1 {

    IVaultRewardPool public vaultRewardPool;
    uint256 public lastBlock = 0;

    constructor (
        address _vaultRewardPool
    ){
        vaultRewardPool = IVaultRewardPool(_vaultRewardPool);
    }

    function getRewards() external {
        // get vault pending BALLE rewards
        vaultRewardPool.getVaultRewards();
        lastBlock = block.number;
    }
    
    function getLastBlock() external view returns(uint256) {
        return lastBlock;
    }
    
}

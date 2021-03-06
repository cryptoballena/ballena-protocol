// contracts/mocks/CakeLPStrategyV2Mock.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.7.4;

import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IPancakeRouter.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IMasterChef.sol";

/**
 * @dev Implementation of a strategy to get yields from farming LP Pools in PancakeSwap.
 * PancakeSwap is an automated market maker (“AMM”) that allows two tokens to be exchanged on the Binance Smart Chain.
 * It is fast, cheap, and allows anyone to participate. PancakeSwap is aiming to be the #1 liquidity provider on BSC.
 *
 * This strategy simply deposits whatever funds it receives from the vault into the selected MasterChef pool.
 * CAKE rewards from providing liquidity are farmed every few minutes, sold and split 50/50. 
 * The corresponding pair of assets are bought and more liquidity is added to the MasterChef pool.
 * 
 * This strat is currently compatible with all LP pools.
 */
contract CakeLPStrategyV2Mock is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /**
     * @dev Tokens Used:
     * {wbnb} - Required for liquidity routing when doing swaps and for sending fee to treasury.
     * {cake} - Token generated by staking our funds. In this case it's the CAKEs token.
     * {balle} - Ballena.io token, used to send performance fee to reward pot contract.
     * {lpPair} - Token that the strategy maximizes. The same token that users deposit in the vault.
     * {lpToken0, lpToken1} - Tokens that the strategy maximizes. IPancakePair tokens
     */
    address public wbnb;
    address public balle;
    address public cake;
    address public lpPair;
    address public lpToken0;
    address public lpToken1;

    /**
     * @dev Third Party Contracts:
     * {unirouter} - PancakeSwap unirouter
     * {masterchef} - MasterChef contract
     * {poolId} - MasterChef pool id
     */
    address public unirouter;
    address public masterchef;
    uint8 public poolId; 

    /**
     * @dev Ballena.io Contracts:
     * {rewardPot} - Reward pot where the strategy fee earnings will go.
     * {treasury} - Address of the Ballena.io treasury
     * {vault} - Address of the vault that controls the strategy's funds.
     */
    //address public immutable rewardPot;
    //address public immutable treasury;
    //address public immutable vault;
    address public vault;

    /**
     * @dev Distribution of fees earned.
     * Current implementation separates 4.0% for fees.
     *
     * {REWARDS_FEE} - 3% goes to BALLE holders through the governance rewards pool.
     * {TREASURY_FEE} - 1% goes to the treasury.
     * {MAX_FEE} - Aux const used to safely calc the correct amounts.
     *
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 10 === 0.1% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     */
    uint constant public REWARDS_FEE  = 750;
    uint constant public TREASURY_FEE = 250;
    uint constant public MAX_FEE      = 1000;

    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

    /**
     * @dev Routes we take to swap tokens using PancakeSwap.
     * {cakeToWbnbRoute} - Route we take to get from {cake} into {wbnb}.
     * {cakeToBalleRoute} - Route we take to get from {cake} into {balle}.
     * {cakeToLp0Route} - Route we take to get from {cake} into {lpToken0}.
     * {cakeToLp1Route} - Route we take to get from {cake} into {lpToken1}.
     */
    address[] public cakeToWbnbRoute;
    address[] public cakeToBalleRoute;
    address[] public cakeToLp0Route;
    address[] public cakeToLp1Route;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    /**
     * @dev Initializes the strategy with the token to maximize.
     */
    constructor(
        address _lpPair
    ) {
        require(_lpPair != address(0), "Illegal address");

        lpPair = _lpPair;
    }


    /**
     * @dev Function needed to init the mock on testing.
     */
    function mock_init(address _vault) public {
        require(_vault != address(0), "Illegal address");
        vault = _vault;
    }        

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * It deposits {lpPair} in the MasterChef to farm {cake}
     */
    function deposit() public whenNotPaused {
        uint256 pairBal = IERC20(lpPair).balanceOf(address(this));

        //if (pairBal > 0) {
        //    IMasterChef(masterchef).deposit(poolId, pairBal);
        //}
    }

    /**
     * @dev Withdraws funds and sents them back to the vault.
     * It withdraws {lpPair} from the MasterChef.
     * The available {lpPair} minus fees is returned to the vault.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 pairBal = IERC20(lpPair).balanceOf(address(this));

        //if (pairBal < _amount) {   
        //    IMasterChef(masterchef).withdraw(poolId, _amount.sub(pairBal));
        //    pairBal = IERC20(lpPair).balanceOf(address(this));
        //}

        if (pairBal > _amount) {
            pairBal = _amount;    
        }
        
        //uint256 withdrawalFee = pairBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
        //IERC20(lpPair).safeTransfer(vault, pairBal.sub(withdrawalFee));
        IERC20(lpPair).safeTransfer(vault, pairBal);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. It claims rewards from the MasterChef.
     * 2. It charges the system fees to simplify the split.
     * 3. It swaps the {cake} token for {lpToken0} & {lpToken1}
     * 4. Adds more liquidity to the pool.
     * 5. It deposits the new LP tokens.
     *//*
    function harvest() external whenNotPaused {
        IMasterChef(masterchef).deposit(poolId, 0);
        chargeFees();
        addLiquidity();
        deposit();

        emit StratHarvest(msg.sender);
    }

    /**
     * @dev Takes out 4.0% as system fees from the rewards. 
     * 1.0% -> Treasury fee
     * 3.0% -> BALLE Holders
     *//*
    function chargeFees() internal {
        uint256 totalFee = IERC20(cake).balanceOf(address(this)).mul(40).div(1000);

        // Treasury portion goes to WBNB
        uint256 treasuryFee = totalFee.mul(TREASURY_FEE).div(MAX_FEE);
        IPancakeRouter(unirouter).swapExactTokensForTokens(treasuryFee, 0, cakeToWbnbRoute, treasury, block.timestamp.add(600));
        // no need to check output amount, all operation go against any output we get
        
        // Reward pool portion goes to BALLE
        uint256 rewardsFee = totalFee.mul(REWARDS_FEE).div(MAX_FEE);
        IPancakeRouter(unirouter).swapExactTokensForTokens(rewardsFee, 0, cakeToBalleRoute, rewardPot, block.timestamp.add(600));
        // no need to check output amount, any qty we get is ok as fee
    }

    /**
     * @dev Swaps {cake} for {lpToken0}, {lpToken1} & {wbnb} using PancakeSwap.
     *//*
    function addLiquidity() internal {   
        uint256 cakeHalf = IERC20(cake).balanceOf(address(this)).div(2);
        
        if (lpToken0 != cake) {
            IPancakeRouter(unirouter).swapExactTokensForTokens(cakeHalf, 0, cakeToLp0Route, address(this), block.timestamp.add(600));
            // no need to check output amount
        }

        if (lpToken1 != cake) {
            IPancakeRouter(unirouter).swapExactTokensForTokens(cakeHalf, 0, cakeToLp1Route, address(this), block.timestamp.add(600));
            // no need to check output amount
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IPancakeRouter(unirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp.add(600));
        // no need to check output amount, all liquidity gain we can archieve will be good
    }

    /**
     * @dev Function to calculate the total underlaying {lpPair} held by the strat.
     * It takes into account both the funds in hand, as the funds allocated in the MasterChef.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfLpPair().add(balanceOfPool());
    }

    /**
     * @dev It calculates how much {lpPair} the contract holds.
     */
    function balanceOfLpPair() public view returns (uint256) {
        return IERC20(lpPair).balanceOf(address(this));
    }

    /**
     * @dev It calculates how much {lpPair} the strategy has allocated in the MasterChef
     */
    function balanceOfPool() public view returns (uint256) {
        //(uint256 _amount, ) = IMasterChef(masterchef).userInfo(poolId, address(this));
        //return _amount;
        return 0;
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the 
     * vault, ready to be migrated to the new strat.
     *//*
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMasterChef(masterchef).emergencyWithdraw(poolId);

        uint256 pairBal = IERC20(lpPair).balanceOf(address(this));
        IERC20(lpPair).transfer(vault, pairBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the MasterChef, leaving rewards behind
     *//*
    function panic() external onlyOwner {
        pause();
        IMasterChef(masterchef).emergencyWithdraw(poolId);
    }

    /**
     * @dev Pauses the strategy.
     *//*
    function pause() public onlyOwner {
        _pause();

        IERC20(lpPair).safeApprove(masterchef, 0);
        IERC20(cake).safeApprove(unirouter, 0);
        IERC20(wbnb).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }

    /**
     * @dev Unpauses the strategy.
     *//*
    function unpause() external onlyOwner {
        _unpause();

        IERC20(lpPair).safeApprove(masterchef, uint(-1));
        IERC20(cake).safeApprove(unirouter, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, uint(-1));

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, uint(-1));
    }*/
}

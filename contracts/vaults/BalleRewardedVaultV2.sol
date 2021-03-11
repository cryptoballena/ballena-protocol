// contracts/vaults/BalleRewardedVaultV2.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.7.4;

import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/ReentrancyGuard.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IVaultRewardPool.sol";

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract BalleRewardedVaultV2 is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    struct StratCandidate {
        address implementation;
        uint proposedTime;
    }

    // The last proposed strategy to switch to.
    StratCandidate public stratCandidate; 
    // The strategy currently in use by the vault.
    address public strategy;
    // The token the vault accepts and looks to maximize.
    IERC20 public immutable token;
    // The minimum time it has to pass before a strat candidate can be approved.
    uint256 public immutable approvalDelay;
    // The BALLE token used for rewards.
    IERC20 public immutable balle;
    // The BALLE token reward pool.
    IVaultRewardPool public immutable vaultRewardPool;

    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardPaid(address indexed user, uint256 reward);
    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);
    
    /**
     * @dev Sets the value of {token} to the token that the vault will
     * hold as underlying value. It initializes the vault's own 'balle' token.
     * This token is minted when someone does a deposit. It is burned in order
     * to withdraw the corresponding portion of the underlying assets.
     * @param _token the token to maximize.
     * @param _strategy the address of the strategy.
     * @param _name the name of the vault token.
     * @param _symbol the symbol of the vault token.
     * @param _approvalDelay the delay before a new strat can be approved.
     * @param _balle the BALLE token for rewards.
     * @param _vaultRewardPool the address of the reward pool for the vault.
     */
    constructor (
        address _token,
        address _strategy,
        string memory _name,
        string memory _symbol,
        uint256 _approvalDelay,
        address _balle,
        address _vaultRewardPool
    ) ERC20(
        string(_name),
        string(_symbol)
    ){
        require(_token != address(0), "Illegal address");
        require(_strategy != address(0), "Illegal address");
        require(_balle != address(0), "Illegal address");
        require(_vaultRewardPool != address(0), "Illegal address");

        token = IERC20(_token);
        strategy = _strategy;
        approvalDelay = _approvalDelay;
        balle = IERC20(_balle);
        vaultRewardPool = IVaultRewardPool(_vaultRewardPool);
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the vault contract balance, the strategy contract balance
     *  and the balance deployed in other contracts as part of the strategy.
     */
    function balance() public view returns (uint) {
        return token.balanceOf(address(this)).add(IStrategy(strategy).balanceOf());
    }

    /**
     * @dev Custom logic in here for how much the vault allows to be borrowed.
     * We return 100% of tokens for now. Under certain conditions we might
     * want to keep some of the system funds at hand in the vault, instead
     * of putting them to work.
     */
    function available() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() external view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : balance().mul(1e18).div(totalSupply());
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     */
    function deposit(uint _amount) public updateReward(msg.sender) {
        uint256 _pool = balance();
        uint256 _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens

        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);

        earn();
    }

    /**
     * @dev Function to send funds into the strategy and put them to work. It's primarily called
     * by the vault's deposit() function.
     */
    function earn() public {
        uint _bal = available();
        token.safeTransfer(strategy, _bal);
        IStrategy(strategy).deposit();
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of balleVAULT
     * tokens are burned in the process.
     */
    function withdraw(uint256 _shares) public updateReward(msg.sender) {
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        uint256 bb = balle.balanceOf(address(this));
        uint256 reward = (bb.mul(_shares)).div(totalSupply());
        if (bb < reward) {
            reward = bb;
        }

        _burn(msg.sender, _shares);

        uint b = token.balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r.sub(b);
            IStrategy(strategy).withdraw(_withdraw);
            uint _after = token.balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        getReward();
        token.safeTransfer(msg.sender, r);
    }

    /** 
     * @dev Sets the candidate for the new strat to use with this vault.
     * @param _implementation The address of the candidate strategy.  
     */
    function proposeStrat(address _implementation) external onlyOwner {
        stratCandidate = StratCandidate({ 
            implementation: _implementation,
            proposedTime: block.timestamp
         });

        emit NewStratCandidate(_implementation);
    }

    /** 
     * @dev It switches the active strat for the strat candidate. After upgrading, the 
     * candidate implementation is set to the 0x00 address, and proposedTime to a time 
     * happening in +100 years for safety. 
     */

    function upgradeStrat() external onlyOwner {
        require(stratCandidate.implementation != address(0), "There is no candidate");
        require(stratCandidate.proposedTime.add(approvalDelay) < block.timestamp, "Delay has not passed");
        
        emit UpgradeStrat(stratCandidate.implementation);

        IStrategy(strategy).retireStrat();
        strategy = stratCandidate.implementation;
        stratCandidate.implementation = address(0);
        stratCandidate.proposedTime = 5000000000;
        
        earn();
    }

    /**
     * @dev This modifier is called before deposit and withdraw so it gets pending rewards and updates distribution.
     */
    modifier updateReward(address _account) {
        require(_account != address(0), "Illegal address");
        // get vault pending BALLE rewards
        vaultRewardPool.getVaultRewards();
        // get rate
        uint256 reward = balle.balanceOf(address(this)).sub(rewardPerTokenStored.mul(totalSupply()));
        uint256 rewardTime = block.timestamp.sub(lastUpdateTime);
        rewardRate = reward.div(rewardTime);
        // distribution
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        rewards[_account] = earned(_account);
        userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        _;
    }

    /**
     * @dev Calculates the corresponding rewards for each token stored on pool.
     *      if block.timestamp is later than lastUpdateTime then increments the reward rate accordingly
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                block.timestamp
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    /**
     * @dev Calculates the earning rewards of the user.
     */
    function earned(address _account) public view returns (uint256) {
        return
            balanceOf(_account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[_account]))
                .div(1e18)
                .add(rewards[_account]);
    }

    /**
     * @dev Withdrawal of rewards.
     */
    function getReward() public updateReward(msg.sender) nonReentrant() {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            balle.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

}
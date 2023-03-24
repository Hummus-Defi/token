// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './interfaces/IVeHum.sol';
import './interfaces/IRewarder.sol';

/*
 * This is a sample contract to be used reward VeHum stakers with an additional token
 *
 * It assumes no minting rights, so requires a set amount of YOUR_TOKEN to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the ABC-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the block reward accordingly so it's fully distributed after 30 days.
 *
 */
contract VeHumRewarder is IRewarder, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable override rewardToken;
    IVeHum public farm;
    bool public immutable isNative;

    /// @notice Info of each farm user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of YOUR_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /// @notice Info of each farm poolInfo.
    /// `accTokenPerShare` Amount of YOUR_TOKEN each LP token is worth.
    /// `lastRewardTimestamp` The last timestamp YOUR_TOKEN was rewarded to the poolInfo.
    struct PoolInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardTimestamp;
    }

    /// @notice Info of the poolInfo.
    PoolInfo public poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    uint256 public tokenPerSec;
    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    modifier onlyFarm() {
        require(msg.sender == address(farm), 'onlyFarm: only Farm can call this function');

        _;
    }

    constructor(
        IERC20 _rewardToken,
        IVeHum _farm,
        uint256 _tokenPerSec,
        bool _isNative
    ) {
        require(Address.isContract(address(_rewardToken)), 'constructor: reward token must be a valid contract');
        require(Address.isContract(address(_farm)), 'constructor: Farm must be a valid contract');

        rewardToken = _rewardToken;
        tokenPerSec = _tokenPerSec;
        farm = _farm;
        isNative = _isNative;
        poolInfo = PoolInfo({lastRewardTimestamp: block.timestamp, accTokenPerShare: 0});
    }

    /// @notice Update reward variables of the given poolInfo.
    /// @return pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;

        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = farm.totalSupply();

            if (lpSupply > 0) {
                uint256 timeElapsed = block.timestamp - pool.lastRewardTimestamp;
                uint256 tokenReward = timeElapsed * tokenPerSec;
                pool.accTokenPerShare = pool.accTokenPerShare + ((tokenReward * ACC_TOKEN_PRECISION) / lpSupply);
            }

            pool.lastRewardTimestamp = block.timestamp;
            poolInfo = pool;
        }
    }

    /// @notice Sets the distribution reward rate. This will also update the poolInfo.
    /// @param _tokenPerSec The number of tokens to distribute per second
    function setRewardRate(uint256 _tokenPerSec) external onlyOwner {
        updatePool();

        uint256 oldRate = tokenPerSec;
        tokenPerSec = _tokenPerSec;

        emit RewardRateUpdated(oldRate, _tokenPerSec);
    }

    /// @notice Function called by farm whenever staker claims harvest. Allows staker to also receive a 2nd reward token
    /// @param _user Address of user
    /// @param _lpAmount Number of LP tokens the user has
    function onHumReward(address _user, uint256 _lpAmount) external override onlyFarm nonReentrant returns (uint256) {
        updatePool();

        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint256 pending;
        uint256 payout;
        if (user.amount > 0) {
            pending =
                ((user.amount * (pool.accTokenPerShare)) / ACC_TOKEN_PRECISION) -
                (user.rewardDebt) +
                (user.unpaidRewards);

            if (isNative) {
                uint256 tokenBalance = address(this).balance;

                if (pending > tokenBalance) {
                    (bool success, ) = _user.call{value: tokenBalance}('');
                    payout = tokenBalance;
                    require(success, 'Transfer failed');
                    user.unpaidRewards = pending - tokenBalance;
                } else {
                    (bool success, ) = _user.call{value: pending}('');
                    payout = pending;
                    require(success, 'Transfer failed');
                    user.unpaidRewards = 0;
                }
            } else {
                uint256 tokenBalance = rewardToken.balanceOf(address(this));

                if (pending > tokenBalance) {
                    rewardToken.safeTransfer(_user, tokenBalance);
                    payout = tokenBalance;
                    user.unpaidRewards = pending - tokenBalance;
                } else {
                    rewardToken.safeTransfer(_user, pending);
                    payout = pending;
                    user.unpaidRewards = 0;
                }
            }
        }

        user.amount = _lpAmount;
        user.rewardDebt = (user.amount * (pool.accTokenPerShare)) / ACC_TOKEN_PRECISION;
        emit OnReward(_user, pending - user.unpaidRewards);
        return payout;
    }

    /// @notice View function to see pending tokens
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingTokens(address _user) external view override returns (uint256 pending) {
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = farm.totalSupply();

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 timeElapsed = block.timestamp - (pool.lastRewardTimestamp);
            uint256 tokenReward = timeElapsed * (tokenPerSec);
            accTokenPerShare = accTokenPerShare + ((tokenReward * (ACC_TOKEN_PRECISION)) / lpSupply);
        }

        pending = ((user.amount * (accTokenPerShare)) / ACC_TOKEN_PRECISION) - (user.rewardDebt) + (user.unpaidRewards);
    }

    /// @notice In case rewarder is stopped before emissions finished, this function allows
    /// withdrawal of remaining tokens.
    function emergencyWithdraw() public onlyOwner {
        if (isNative) {
            (bool success, ) = msg.sender.call{value: address(this).balance}('');
            require(success, 'Transfer failed');
        } else {
            rewardToken.safeTransfer(address(msg.sender), rewardToken.balanceOf(address(this)));
        }
    }

    /// @notice View function to see balance of reward token.
    function balance() external view returns (uint256) {
        if (isNative) {
            return address(this).balance;
        } else {
            return rewardToken.balanceOf(address(this));
        }
    }

    /// @notice payable function needed to receive
    receive() external payable {}
}

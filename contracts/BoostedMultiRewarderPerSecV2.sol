// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './BoostedMultiRewarderPerSec.sol';

/**
 * This is a sample contract to be used in the MasterHummus contract for partners to reward
 * stakers with their native token alongside HUM.
 *
 * It assumes no minting rights, so requires a set amount of reward tokens to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the HUM-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the block reward accordingly so it's fully distributed after 30 days.
 *
 * - This contract has no knowledge on the LP amount and MasterHummus is
 *   responsible to pass the amount into this contract
 * - Supports multiple reward tokens
 * - Support boosted pool. The dilutingRepartition can be different from that of MasterHummusV4
 * - Resets token per sec to zero if token balance cannot fullfill rewards that are due
 */
contract BoostedMultiRewarderPerSecV2 is BoostedMultiRewarderPerSec {
    using SafeERC20 for IERC20;

    constructor(
        IMasterHummusV3 _MH,
        IERC20 _lpToken,
        uint40 _startTimestamp,
        uint16 _dilutingRepartition,
        IERC20 _rewardToken,
        uint96 _tokenPerSec
    ) BoostedMultiRewarderPerSec(_MH, _lpToken, _startTimestamp, _dilutingRepartition, _rewardToken, _tokenPerSec) {}

    /// @notice Sets the distribution reward rate. This will also update the poolInfo.
    /// @param _tokenPerSec The number of tokens to distribute per second
    function setRewardRate(uint256 _tokenId, uint96 _tokenPerSec) external override onlyOperatorOrOwner {
        require(_tokenPerSec <= 10000e18, 'reward rate too high'); // in case of accTokenPerShare overflow
        _setRewardRate(_tokenId, _tokenPerSec);
    }

    function _setRewardRate(uint256 _tokenId, uint96 _tokenPerSec) internal {
        _updatePool();

        uint256 oldRate = poolInfo[_tokenId].tokenPerSec;
        poolInfo[_tokenId].tokenPerSec = _tokenPerSec;

        emit RewardRateUpdated(address(poolInfo[_tokenId].rewardToken), oldRate, _tokenPerSec);
    }

    /// @notice Function called by MasterHummus whenever staker claims HUM harvest.
    /// @notice Allows staker to also receive a 2nd reward token.
    /// @dev Assume lpSupply and sumOfFactors isn't updated yet when this function is called
    /// @param _user Address of user
    /// @param _lpAmount Number of LP tokens the user has
    function onHumReward(
        address _user,
        uint256 _lpAmount,
        uint256 _newLpAmount,
        uint256 _factor,
        uint256 _newFactor
    ) external override onlyMH nonReentrant returns (uint256[] memory rewards) {
        _updatePool();

        uint256 length = poolInfo.length;
        rewards = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            PoolInfo storage pool = poolInfo[i];
            UserInfo storage user = userInfo[i][_user];
            IERC20 rewardToken = pool.rewardToken;

            // if user has activated the pool, update rewards
            if (user.rewardDebt > 0) {
                uint256 pending = ((_lpAmount * pool.accTokenPerShare + _factor * pool.accTokenPerFactorShare) /
                    ACC_TOKEN_PRECISION) +
                    user.claimable -
                    user.rewardDebt;

                if (address(rewardToken) == address(0)) {
                    // is native token
                    uint256 tokenBalance = address(this).balance;
                    if (pending >= tokenBalance) {
                        _safeTransferMetisWithFallback(_user, tokenBalance);
                        rewards[i] = tokenBalance;
                        user.claimable = toUint128(pending - tokenBalance);
                        // In case partners forget to replenish token, pause token emission
                        // Note that some accumulated rewards might not be able to distribute
                        _setRewardRate(i, 0);
                    } else {
                        _safeTransferMetisWithFallback(_user, pending);
                        rewards[i] = pending;
                        user.claimable = 0;
                    }
                } else {
                    // ERC20 token
                    uint256 tokenBalance = rewardToken.balanceOf(address(this));
                    if (pending >= tokenBalance) {
                        rewardToken.safeTransfer(_user, tokenBalance);
                        rewards[i] = tokenBalance;
                        user.claimable = toUint128(pending - tokenBalance);
                        // In case partners forget to replenish token, pause token emission
                        // Note that some accumulated rewards might not be able to distribute
                        _setRewardRate(i, 0);
                    } else {
                        rewardToken.safeTransfer(_user, pending);
                        rewards[i] = pending;
                        user.claimable = 0;
                    }
                }
            }

            user.rewardDebt = toUint128(
                (_newLpAmount * pool.accTokenPerShare + _newFactor * pool.accTokenPerFactorShare) / ACC_TOKEN_PRECISION
            );
            emit OnReward(address(rewardToken), _user, rewards[i]);
        }
    }
}
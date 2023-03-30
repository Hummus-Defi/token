// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@rari-capital/solmate/src/utils/FixedPointMathLib.sol';
import './libraries/SafeOwnableUpgradeable.sol';
import './interfaces/IAsset.sol';
import './interfaces/IVeHum.sol';
import './interfaces/IMasterHummusV3.sol';
import './interfaces/IBoostedMultiRewarder.sol';
import './interfaces/IVoter.sol';

/// MasterHummus is a boss. He says "go f your blocks maki boy, I'm gonna use timestamp instead"
/// In addition, he feeds himself from Vote-Escrowed Hummus. So, veHum holders boost their (non-dialuting) emissions.
/// This contract rewards users in function of their amount of lp staked (dialuting pool) factor (non-dialuting pool)
/// Factor and sumOfFactors are updated by contract VeHum.sol after any veHum minting/burning (veERC20Upgradeable hook).
/// Note that it's ownable and the owner wields tremendous power. The ownership
/// will be transferred to a governance smart contract once Hummus is sufficiently
/// distributed and the community can show to govern itself.
/// ## Updates
/// - V3 is an improved version of MasterHummus(V1), which packs storage variables in order to save gas.
/// - Compatible with gauge voting
contract MasterHummusV3 is
    Initializable,
    SafeOwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IMasterHummusV3
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // The strongest hummus out there (hum token).
    IERC20 public hum;
    // The strongest vote-escrowed hummus out there (veHum token)
    IVeHum public veHum;
    // New Master Hummus address for future migrations
    IMasterHummusV3 public newMasterHummus;
    // Address of Voter
    address public voter;
    // Emissions: dilutingRepartition and non-dilutingRepartition must add to 1000 => 100%
    // Dialuting emissions repartition (e.g. 300 for 30%)
    uint16 public dilutingRepartition;
    // The maximum number of pools, in case updateFactor() exceeds block gas limit
    uint256 public maxPoolLength;
    // Set of all LP tokens that have been added as pools
    EnumerableSet.AddressSet private lpTokens;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event Add(uint256 indexed pid, IAsset indexed lpToken, IBoostedMultiRewarder indexed rewarder);
    event SetRewarder(uint256 indexed pid, IBoostedMultiRewarder indexed rewarder);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event DepositFor(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateEmissionRepartition(address indexed user, uint256 dilutingRepartition, uint256 nonDilutingRepartition);
    event UpdateVeHUM(address indexed user, address oldVeHUM, address newVeHUM);

    /// @dev Modifier ensuring that certain function can only be called by VeHum
    modifier onlyVeHum() {
        require(address(veHum) == msg.sender, 'notVeHum: wut?');
        _;
    }

    /// @dev Modifier ensuring that certain function can only be called by Voter
    modifier onlyVoter() {
        require(address(voter) == msg.sender, 'notVoter: wut?');
        _;
    }

    function initialize(IERC20 _hum, IVeHum _veHum, address _voter, uint16 _dilutingRepartition) public initializer {
        require(address(_hum) != address(0), 'hum address cannot be zero');
        require(address(_veHum) != address(0), 'veHum address cannot be zero');
        require(address(_voter) != address(0), 'voter address cannot be zero');
        require(_dilutingRepartition <= 1000, 'dialuting repartition must be in range 0, 1000');

        __Ownable_init();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();

        hum = _hum;
        veHum = _veHum;
        voter = _voter;
        dilutingRepartition = _dilutingRepartition;
        maxPoolLength = 50;
    }

    /**
     * @dev pause pool, restricting certain operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause pool, enabling certain operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    function setNewMasterHummus(IMasterHummusV3 _newMasterHummus) external onlyOwner {
        newMasterHummus = _newMasterHummus;
    }

    function setMaxPoolLength(uint256 _maxPoolLength) external onlyOwner {
        require(poolInfo.length <= _maxPoolLength);
        maxPoolLength = _maxPoolLength;
    }

    function nonDilutingRepartition() external view returns (uint256) {
        return 1000 - dilutingRepartition;
    }

    /// @notice returns pool length
    function poolLength() external view override returns (uint256) {
        return poolInfo.length;
    }

    function getPoolId(address _lp) external view returns (uint256) {
        require(lpTokens.contains(address(_lp)), 'invalid lp');
        return lpTokens._inner._indexes[bytes32(uint256(uint160(_lp)))] - 1;
    }

    function getUserInfo(uint256 _pid, address _user) external view returns (UserInfo memory) {
        return userInfo[_pid][_user];
    }

    function getSumOfFactors(uint256 _pid) external view override returns (uint256) {
        return poolInfo[_pid].sumOfFactors;
    }

    /// @notice Add a new lp to the pool. Can only be called by the owner.
    /// @dev Reverts if the same LP token is added more than once.
    /// @param _lpToken the corresponding lp token
    /// @param _rewarder the rewarder
    function add(IAsset _lpToken, IBoostedMultiRewarder _rewarder) public onlyOwner {
        require(Address.isContract(address(_lpToken)), 'add: LP token must be a valid contract');
        require(
            Address.isContract(address(_rewarder)) || address(_rewarder) == address(0),
            'add: rewarder must be contract or zero'
        );
        require(!lpTokens.contains(address(_lpToken)), 'add: LP already added');
        require(poolInfo.length < maxPoolLength, 'add: exceed max pool');

        // update PoolInfo with the new LP
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                rewarder: _rewarder,
                sumOfFactors: 0,
                accHumPerShare: 0,
                accHumPerFactorShare: 0
            })
        );

        // add lpToken to the lpTokens enumerable set
        lpTokens.add(address(_lpToken));
        emit Add(poolInfo.length - 1, _lpToken, _rewarder);
    }

    /// @notice Update the given pool's rewarder
    /// @param _pid the pool id
    /// @param _rewarder the rewarder
    function setRewarder(uint256 _pid, IBoostedMultiRewarder _rewarder) public onlyOwner {
        require(
            Address.isContract(address(_rewarder)) || address(_rewarder) == address(0),
            'set: rewarder must be contract or zero'
        );

        PoolInfo storage pool = poolInfo[_pid];

        pool.rewarder = _rewarder;
        emit SetRewarder(_pid, _rewarder);
    }

    /// @notice Get bonus token info from the rewarder contract for a given pool, if it is a double reward farm
    /// @param _pid the pool id
    function rewarderBonusTokenInfo(
        uint256 _pid
    ) public view override returns (IERC20[] memory bonusTokenAddresses, string[] memory bonusTokenSymbols) {
        PoolInfo storage pool = poolInfo[_pid];
        if (address(pool.rewarder) == address(0)) {
            return (bonusTokenAddresses, bonusTokenSymbols);
        }

        bonusTokenAddresses = pool.rewarder.rewardTokens();

        uint256 len = bonusTokenAddresses.length;
        bonusTokenSymbols = new string[](len);
        for (uint256 i; i < len; ++i) {
            bonusTokenSymbols[i] = IERC20Metadata(address(bonusTokenAddresses[i])).symbol();
        }
    }

    /// @notice Update reward variables for all pools.
    /// @dev Be careful of gas spending!
    function massUpdatePools() external override {
        uint256 length = poolInfo.length;
        for (uint256 pid; pid < length; ++pid) {
            _updatePool(pid);
        }
    }

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @param _pid the pool id
    function updatePool(uint256 _pid) external override {
        _updatePool(_pid);
    }

    function _updatePool(uint256 _pid) private {
        PoolInfo storage pool = poolInfo[_pid];
        IVoter(voter).distribute(address(pool.lpToken));
    }

    /// @dev We might distribute HUM over a period of time to prevent front-running
    /// Refer to synthetix/StakingRewards.sol notifyRewardAmount
    /// Note: This looks safe from reentrancy.
    function notifyRewardAmount(address _lpToken, uint256 _amount) external override {
        require(_amount > 0, 'MasterHummus: zero amount');
        require(msg.sender == voter, 'MasterHummus: only voter');

        // this line reverts if asset is not in the list
        uint256 pid = lpTokens._inner._indexes[bytes32(uint256(uint160(_lpToken)))] - 1;
        PoolInfo storage pool = poolInfo[pid];

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            return;
        }

        // update accHumPerShare to reflect dialuting rewards
        pool.accHumPerShare += toUint128((_amount * 1e12 * dilutingRepartition) / (lpSupply * 1000));

        // update accHumPerFactorShare to reflect non-dialuting rewards
        if (pool.sumOfFactors > 0) {
            pool.accHumPerFactorShare += toUint128(
                (_amount * 1e12 * (1000 - dilutingRepartition)) / (pool.sumOfFactors * 1000)
            );
        }

        // Event is not emitted. as Voter should have already emitted it
    }

    /// @notice Helper function to migrate fund from multiple pools to the new MasterHummus.
    /// @notice user must initiate transaction from masterchef
    /// @dev Assume the orginal MasterHummus has stopped emisions
    /// hence we skip IVoter(voter).distribute() to save gas cost
    function migrate(uint256[] calldata _pids) external override nonReentrant {
        require(address(newMasterHummus) != (address(0)), 'to where?');

        _multiClaim(_pids);
        for (uint256 i; i < _pids.length; ++i) {
            uint256 pid = _pids[i];
            UserInfo storage user = userInfo[pid][msg.sender];

            if (user.amount > 0) {
                PoolInfo storage pool = poolInfo[pid];
                pool.lpToken.approve(address(newMasterHummus), user.amount);
                newMasterHummus.depositFor(pid, user.amount, msg.sender);

                pool.sumOfFactors -= toUint128(user.factor);

                // remove user
                delete userInfo[pid][msg.sender];
            }
        }
    }

    /// @notice Deposit LP tokens to MasterChef for HUM allocation on behalf of user
    /// @dev user must initiate transaction from masterchef
    /// @param _pid the pool id
    /// @param _amount amount to deposit
    /// @param _user the user being represented
    function depositFor(uint256 _pid, uint256 _amount, address _user) external override nonReentrant whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        // update pool in case user has deposited
        IVoter(voter).distribute(address(pool.lpToken));
        _updateFor(_pid, _user, user.amount + _amount);

        // SafeERC20 is not needed as Asset will revert if transfer fails
        pool.lpToken.transferFrom(msg.sender, address(this), _amount);
        emit DepositFor(_user, _pid, _amount);
    }

    /// @notice Deposit LP tokens to MasterChef for HUM allocation.
    /// @dev it is possible to call this function with _amount == 0 to claim current rewards
    /// @param _pid the pool id
    /// @param _amount amount to deposit
    function deposit(
        uint256 _pid,
        uint256 _amount
    ) external override nonReentrant whenNotPaused returns (uint256 reward, uint256[] memory additionalRewards) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        IVoter(voter).distribute(address(pool.lpToken));
        (reward, additionalRewards) = _updateFor(_pid, msg.sender, user.amount + _amount);

        // SafeERC20 is not needed as Asset will revert if transfer fails
        pool.lpToken.transferFrom(address(msg.sender), address(this), _amount);
        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @notice claims rewards for multiple pids
    /// @param _pids array pids, pools to claim
    function multiClaim(
        uint256[] calldata _pids
    )
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 reward, uint256[] memory amounts, uint256[][] memory additionalRewards)
    {
        return _multiClaim(_pids);
    }

    /// @notice private function to claim rewards for multiple pids
    /// @param _pids array pids, pools to claim
    function _multiClaim(
        uint256[] memory _pids
    ) private returns (uint256 reward, uint256[] memory amounts, uint256[][] memory additionalRewards) {
        // accumulate rewards for each one of the pids in pending
        amounts = new uint256[](_pids.length);
        additionalRewards = new uint256[][](_pids.length);
        for (uint256 i; i < _pids.length; ++i) {
            PoolInfo storage pool = poolInfo[_pids[i]];
            IVoter(voter).distribute(address(pool.lpToken));

            UserInfo storage user = userInfo[_pids[i]][msg.sender];
            if (user.amount > 0) {
                // increase pending to send all rewards once
                uint256 poolRewards = ((uint256(user.amount) *
                    pool.accHumPerShare +
                    uint256(user.factor) *
                    pool.accHumPerFactorShare) / 1e12) +
                    user.claimableHum -
                    user.rewardDebt;

                user.claimableHum = 0;

                // update reward debt
                user.rewardDebt = toUint128(
                    (uint256(user.amount) * pool.accHumPerShare + uint256(user.factor) * pool.accHumPerFactorShare) /
                        1e12
                );

                // increase reward
                reward += poolRewards;

                amounts[i] = poolRewards;
                emit Harvest(msg.sender, _pids[i], amounts[i]);

                // if exist, update external rewarder
                IBoostedMultiRewarder rewarder = pool.rewarder;
                if (address(rewarder) != address(0)) {
                    additionalRewards[i] = rewarder.onHumReward(
                        msg.sender,
                        user.amount,
                        user.amount,
                        user.factor,
                        user.factor
                    );
                }
            }
        }
        // transfer all rewards
        // SafeERC20 is not needed as HUM will revert if transfer fails
        hum.transfer(payable(msg.sender), reward);
    }

    /// @notice View function to see pending HUMs on frontend.
    /// @param _pid the pool id
    /// @param _user the user address
    function pendingTokens(
        uint256 _pid,
        address _user
    )
        external
        view
        override
        returns (
            uint256 pendingHum,
            IERC20[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols,
            uint256[] memory pendingBonusTokens
        )
    {
        PoolInfo storage pool = poolInfo[_pid];

        // calculate accHumPerShare and accHumPerFactorShare
        uint256 pendingHumForLp = IVoter(voter).pendingHum(address(pool.lpToken));
        uint256 accHumPerShare = pool.accHumPerShare;
        uint256 accHumPerFactorShare = pool.accHumPerFactorShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply != 0) {
            accHumPerShare += (pendingHumForLp * 1e12 * dilutingRepartition) / (lpSupply * 1000);
        }
        if (pool.sumOfFactors > 0) {
            accHumPerFactorShare +=
                (pendingHumForLp * 1e12 * (1000 - dilutingRepartition)) /
                (pool.sumOfFactors * 1000);
        }

        // get pendingHum
        UserInfo storage user = userInfo[_pid][_user];
        pendingHum =
            ((uint256(user.amount) * accHumPerShare + uint256(user.factor) * accHumPerFactorShare) / 1e12) +
            user.claimableHum -
            user.rewardDebt;

        (bonusTokenAddresses, bonusTokenSymbols) = rewarderBonusTokenInfo(_pid);

        // get pendingBonusToken
        IBoostedMultiRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            pendingBonusTokens = rewarder.pendingTokens(_user, user.amount, user.factor);
        }
    }

    /**
     * @notice internal function to withdraw lps on behalf of user
     * @dev pending rewards are transfered to user, lps are transfered to caller
     * @param _pid the pool id
     * @param _user the user being represented
     * @param _caller caller's address
     * @param _amount amount to withdraw
     */
    function _withdrawFor(
        uint256 _pid,
        address _user,
        address _caller,
        uint256 _amount
    ) internal returns (uint256 reward, uint256[] memory additionalRewards) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.amount >= _amount, 'withdraw: not enough balance');

        IVoter(voter).distribute(address(pool.lpToken));
        (reward, additionalRewards) = _updateFor(_pid, _user, user.amount - _amount);

        // SafeERC20 is not needed as Asset will revert if transfer fails
        pool.lpToken.transfer(_caller, _amount);
        emit Withdraw(_user, _pid, _amount);
    }

    /// @notice Distribute HUM rewards and Update user balance
    function _updateFor(
        uint256 _pid,
        address _user,
        uint256 _amount
    ) internal returns (uint256 reward, uint256[] memory additionalRewards) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        // Harvest HUM
        if (user.amount > 0 || user.claimableHum > 0) {
            reward =
                ((uint256(user.amount) * pool.accHumPerShare + uint256(user.factor) * pool.accHumPerFactorShare) /
                    1e12) +
                user.claimableHum -
                user.rewardDebt;
            user.claimableHum = 0;

            // SafeERC20 is not needed as HUM will revert if transfer fails
            hum.transfer(payable(_user), reward);
            emit Harvest(_user, _pid, reward);
        }

        // update amount of lp staked
        uint256 oldAmount = user.amount;
        user.amount = toUint128(_amount);

        // update sumOfFactors
        uint128 oldFactor = user.factor;
        user.factor = toUint128(FixedPointMathLib.sqrt(user.amount * veHum.balanceOf(_user)));

        // update reward debt
        user.rewardDebt = toUint128(
            (uint256(user.amount) * pool.accHumPerShare + uint256(user.factor) * pool.accHumPerFactorShare) / 1e12
        );

        // update rewarder before we update lpSupply and sumOfFactors
        IBoostedMultiRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            additionalRewards = rewarder.onHumReward(_user, oldAmount, _amount, oldFactor, user.factor);
        }

        pool.sumOfFactors = toUint128(pool.sumOfFactors + user.factor - oldFactor);
    }

    /// @notice Withdraw LP tokens from MasterHummus.
    /// @notice Automatically harvest pending rewards and sends to user
    /// @param _pid the pool id
    /// @param _amount the amount to withdraw
    function withdraw(
        uint256 _pid,
        uint256 _amount
    ) external override nonReentrant whenNotPaused returns (uint256 reward, uint256[] memory additionalRewards) {
        (reward, additionalRewards) = _withdrawFor(_pid, msg.sender, msg.sender, _amount);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param _pid the pool id
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        // reset rewarder before we update lpSupply and sumOfFactors
        IBoostedMultiRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onHumReward(msg.sender, user.amount, 0, user.factor, 0);
        }

        // SafeERC20 is not needed as Asset will revert if transfer fails
        pool.lpToken.transfer(address(msg.sender), user.amount);

        // update non-dialuting factor
        pool.sumOfFactors -= user.factor;

        user.amount = 0;
        user.factor = 0;
        user.rewardDebt = 0;

        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    }

    /// @notice updates emission repartition
    /// @param _dilutingRepartition the future dialuting repartition
    function updateEmissionRepartition(uint16 _dilutingRepartition) external onlyOwner {
        require(_dilutingRepartition <= 1000);
        dilutingRepartition = _dilutingRepartition;
        emit UpdateEmissionRepartition(msg.sender, _dilutingRepartition, 1000 - _dilutingRepartition);
    }

    /// @notice updates veHum address
    /// @param _newVeHum the new VeHum address
    function setVeHum(IVeHum _newVeHum) external onlyOwner {
        require(address(_newVeHum) != address(0));
        IVeHum oldVeHum = veHum;
        veHum = _newVeHum;
        emit UpdateVeHUM(msg.sender, address(oldVeHum), address(_newVeHum));
    }

    /// @notice updates factor after any veHum token operation (minting/burning)
    /// @param _user the user to update
    /// @param _newVeHumBalance the amount of veHUM
    /// @dev can only be called by veHum
    function updateFactor(address _user, uint256 _newVeHumBalance) external override onlyVeHum {
        // loop over each pool : beware gas cost!
        uint256 length = poolInfo.length;

        for (uint256 pid = 0; pid < length; ) {
            UserInfo storage user = userInfo[pid][_user];

            // skip if user doesn't have any deposit in the pool
            if (user.amount > 0) {
                PoolInfo storage pool = poolInfo[pid];

                // first, update pool
                IVoter(voter).distribute(address(pool.lpToken));

                // calculate pending
                uint256 pending = ((uint256(user.amount) *
                    pool.accHumPerShare +
                    uint256(user.factor) *
                    pool.accHumPerFactorShare) / 1e12) - user.rewardDebt;
                // increase claimableHum
                user.claimableHum += toUint128(pending);

                // update non-dialuting pool factor
                uint128 oldFactor = user.factor;
                user.factor = toUint128(FixedPointMathLib.sqrt(user.amount * _newVeHumBalance));

                // update reward debt, take into account newFactor
                user.rewardDebt = toUint128(
                    (uint256(user.amount) * pool.accHumPerShare + uint256(user.factor) * pool.accHumPerFactorShare) /
                        1e12
                );

                // update rewarder before we update sumOfFactors
                IBoostedMultiRewarder rewarder = pool.rewarder;
                if (address(rewarder) != address(0)) {
                    rewarder.onUpdateFactor(_user, user.amount, oldFactor, user.factor);
                }

                pool.sumOfFactors = pool.sumOfFactors + user.factor - oldFactor;
            }

            unchecked {
                ++pid;
            }
        }
    }

    /// @notice In case we need to manually migrate HUM funds from MasterChef
    /// Sends all remaining hum from the contract to the owner
    function emergencyHumWithdraw() external onlyOwner {
        // SafeERC20 is not needed as HUM will revert if transfer fails
        hum.transfer(address(msg.sender), hum.balanceOf(address(this)));
    }

    function version() external pure returns (uint256) {
        return 3;
    }

    function toUint128(uint256 val) internal pure returns (uint128) {
        if (val > type(uint128).max) revert('uint128 overflow');
        return uint128(val);
    }
}

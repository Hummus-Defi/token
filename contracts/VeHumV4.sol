// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './VeERC20Upgradeable.sol';
import './Whitelist.sol';
import './interfaces/IMasterHummus.sol';
import './libraries/Math.sol';
import './libraries/SafeOwnableUpgradeable.sol';
import './interfaces/IVeHumV4.sol';
import './interfaces/IHummusNFT.sol';
import './interfaces/IRewarder.sol';

/// @title VeHumV4
/// @notice Hummus Venom: the staking contract for HUM, as well as the token used for governance.
/// Note Venom does not seem to hurt the Hummus, it only makes it stronger.
/// Allows depositing/withdraw of hum and staking/unstaking ERC721.
/// Here are the rules of the game:
/// If you stake hum, you generate veHum at the current `generationRate` until you reach `maxStakeCap`
/// If you unstake any amount of hum, you loose all of your veHum.
/// Note that it's ownable and the owner wields tremendous power. The ownership
/// will be transferred to a governance smart contract once Hummus is sufficiently
/// distributed and the community can show to govern itself.
/// VeHumV4 updates
/// - User can lock HUM and instantly mint veHUM.
/// - API change:
///   - maxCap => maxStakeCap
///   - isUser => isUserStaking
contract VeHumV4 is
    Initializable,
    SafeOwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    VeERC20Upgradeable,
    IVeHumV4
{
    // Staking user info
    struct UserInfo {
        uint256 amount; // hum staked by user
        uint256 lastRelease; // time of last veHum claim or first deposit if user has not claimed yet
        // the id of the currently staked nft
        // important note: the id is offset by +1 to handle tokenID = 0
        // stakedNftId = 0 (default value) means that no NFT is staked
        uint256 stakedNftId;
    }

    // Locking user info
    struct LockedPosition {
        uint128 initialLockTime;
        uint128 unlockTime;
        uint128 humLocked;
        uint128 veHumAmount;
    }

    /// @notice the hum token
    IERC20 public hum;

    /// @notice the masterHummus contract
    IMasterHummus public masterHummus;

    /// @notice the NFT contract
    IHummusNFT public nft;

    /// @notice max veHum to staked hum ratio
    /// Note if user has 10 hum staked, they can only have a max of 10 * maxStakeCap veHum in balance
    uint256 public maxStakeCap;

    /// @notice the rate of veHum generated per second, per hum staked
    uint256 public generationRate;

    /// @notice invVvoteThreshold threshold.
    /// @notice voteThreshold is the tercentage of cap from which votes starts to count for governance proposals.
    /// @dev inverse of the threshold to apply.
    /// Example: th = 5% => (1/5) * 100 => invVoteThreshold = 20
    /// Example 2: th = 3.03% => (1/3.03) * 100 => invVoteThreshold = 33
    /// Formula is invVoteThreshold = (1 / th) * 100
    uint256 public invVoteThreshold;

    /// @notice whitelist wallet checker
    /// @dev contract addresses are by default unable to stake hum, they must be previously whitelisted to stake hum
    Whitelist public whitelist;

    /// @notice user info mapping
    // note Staking user info
    mapping(address => UserInfo) public users;

    /// @notice token rewarder address
    IRewarder public rewarder;

    /// @notice voter address
    address public voter;

    /// @notice amount of vote used currently for each user
    mapping(address => uint256) public usedVote;

    /// @notice store the last block when a contract stake NFT
    mapping(address => uint256) internal lastBlockToStakeNftByContract;

    // Note used to prevent storage collision
    uint256[2] private __gap;

    /// @notice min and max lock days
    uint128 public minLockDays;
    uint128 public maxLockDays;

    /// @notice the max cap for locked positions
    uint256 public maxLockCap;

    /// @notice Locked HUM user info
    mapping(address => LockedPosition) public lockedPositions;

    /// @notice total amount of hum locked
    uint256 public totalLockedHum;

    /// @notice events describing staking, unstaking and claiming
    event Staked(address indexed user, uint256 indexed amount);
    event Unstaked(address indexed user, uint256 indexed amount);
    event Claimed(address indexed user, uint256 indexed amount);

    /// @notice events describing NFT staking and unstaking
    event StakedNft(address indexed user, uint256 indexed nftId);
    event UnstakedNft(address indexed user, uint256 indexed nftId);

    /// @notice events describing locking mechanics
    event Lock(address indexed user, uint256 unlockTime, uint256 amount, uint256 veHumToMint);
    event ExtendLock(address indexed user, uint256 daysToExtend, uint256 unlockTime, uint256 veHumToMint);
    event AddToLock(address indexed user, uint256 amountAdded, uint256 veHumToMint);
    event Unlock(address indexed user, uint256 unlockTime, uint256 amount, uint256 veHumToBurn);

    function initialize(
        IERC20 _hum,
        IMasterHummus _masterHummus,
        IHummusNFT _nft
    ) public initializer {
        require(address(_masterHummus) != address(0), 'zero address');
        require(address(_hum) != address(0), 'zero address');

        // Initialize veHUM
        __ERC20_init('Vote-Escrowed Hummus', 'veHUM');
        __Ownable_init();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();

        // set generationRate (veHum per sec per hum staked)
        generationRate = 3888888888888;

        // set maxStakeCap
        maxStakeCap = 100;

        // set inv vote threshold
        // invVoteThreshold = 20 => th = 5
        invVoteThreshold = 20;

        // set master hummus
        masterHummus = _masterHummus;

        // set hum
        hum = _hum;

        // set nft, can be zero address at first
        nft = _nft;
    }

    function _verifyVoteIsEnough(address _user) internal view {
        require(balanceOf(_user) >= usedVote[_user], 'VeHum: not enough vote');
    }

    function _onlyVoter() internal view {
        require(msg.sender == voter, 'VeHum: caller is not voter');
    }

    function initializeLockDays() public onlyOwner {
        minLockDays = 7; // 1 week
        maxLockDays = 357; // 357/(365/12) ~ 11.7 months
        maxLockCap = 120; // < 12 month max lock

        // ~18 month max stake, can set separately
        maxStakeCap = 180;
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

    /// @notice set min and max lock days
    function setLockDaysAndCap(
        uint256 _minLockDays,
        uint256 _maxLockDays,
        uint256 _maxLockCap
    ) external onlyOwner {
        require(_minLockDays < _maxLockDays && _maxLockDays < type(uint128).max, 'lock days are invalid');
        minLockDays = uint128(_minLockDays);
        maxLockDays = uint128(_maxLockDays);
        maxLockCap = _maxLockCap;
    }

    /// @notice sets masterPlatpus address
    /// @param _masterHummus the new masterHummus address
    function setMasterHummus(IMasterHummus _masterHummus) external onlyOwner {
        require(address(_masterHummus) != address(0), 'zero address');
        masterHummus = _masterHummus;
    }

    /// @notice sets NFT contract address
    /// @param _nft the new NFT contract address
    function setNftAddress(IHummusNFT _nft) external onlyOwner {
        require(address(_nft) != address(0), 'zero address');
        nft = _nft;
    }

    /// @notice sets voter contract address
    /// @param _voter the new NFT contract address
    function setVoter(address _voter) external onlyOwner {
        require(address(_voter) != address(0), 'zero address');
        voter = _voter;
    }

    /// @notice sets whitelist address
    /// @param _whitelist the new whitelist address
    function setWhitelist(Whitelist _whitelist) external onlyOwner {
        require(address(_whitelist) != address(0), 'zero address');
        whitelist = _whitelist;
    }

    /// @notice sets rewarder address
    /// @param _rewarder the new whitelist address
    function setRewarder(IRewarder _rewarder) external onlyOwner {
        require(address(_rewarder) != address(0), 'zero address');
        rewarder = _rewarder;
    }

    /// @notice sets maxStakeCap
    /// @param _maxStakeCap the new max ratio
    function setMaxStakeCap(uint256 _maxStakeCap) external onlyOwner {
        require(_maxStakeCap != 0, 'max cap cannot be zero');
        maxStakeCap = _maxStakeCap;
    }

    /// @notice sets generation rate
    /// @param _generationRate the new max ratio
    function setGenerationRate(uint256 _generationRate) external onlyOwner {
        require(_generationRate != 0, 'generation rate cannot be zero');
        generationRate = _generationRate;
    }

    /// @notice sets invVoteThreshold
    /// @param _invVoteThreshold the new var
    /// Formula is invVoteThreshold = (1 / th) * 100
    function setInvVoteThreshold(uint256 _invVoteThreshold) external onlyOwner {
        require(_invVoteThreshold != 0, 'invVoteThreshold cannot be zero');
        invVoteThreshold = _invVoteThreshold;
    }

    /// @notice checks whether user _addr has hum lock
    /// @param _addr the user address to check
    /// @return true if the user has hum in lock, false otherwise
    function isUserLocking(address _addr) public view override returns (bool) {
        return lockedPositions[_addr].humLocked > 0;
    }

    /// @notice checks whether user _addr has hum staked
    /// @param _addr the user address to check
    /// @return true if the user has hum in stake, false otherwise
    function isUserStaking(address _addr) public view override returns (bool) {
        return users[_addr].amount > 0;
    }

    /// @notice [Deprecated] return the result of `isUserStaking()` for backward compatibility
    function isUser(address _addr) external view returns (bool) {
        return isUserStaking(_addr);
    }

    /// @notice [Deprecated] return the `maxStakeCap` for backward compatibility
    function maxCap() external view returns (uint256) {
        return maxStakeCap;
    }

    /// @notice returns locked amount of hum for user
    /// @param _addr the user address to check
    /// @return locked amount of hum
    function getLockedHum(address _addr) external view override returns (uint256) {
        return lockedPositions[_addr].humLocked;
    }

    /// @notice returns staked amount of hum for user
    /// @param _addr the user address to check
    /// @return staked amount of hum
    function getStakedHum(address _addr) external view override returns (uint256) {
        return users[_addr].amount;
    }

    /// @dev explicity override multiple inheritance
    function totalSupply() public view override(VeERC20Upgradeable, IVeERC20) returns (uint256) {
        return super.totalSupply();
    }

    /// @dev explicity override multiple inheritance
    function balanceOf(address account) public view override(VeERC20Upgradeable, IVeERC20) returns (uint256) {
        return super.balanceOf(account);
    }

    /// @notice returns expected veHUM amount to be minted given amount and number of days to lock
    function _expectedVeHumAmount(uint256 _amount, uint256 _lockSeconds) private view returns (uint256) {
        return Math.wmul(_amount, _lockSeconds * generationRate);
    }

    function quoteExpectedVeHumAmount(uint256 _amount, uint256 _lockDays) external view returns (uint256) {
        return _expectedVeHumAmount(_amount, _lockDays * 1 minutes);
    }

    /// @notice locks HUM in the contract, immediately minting veHUM
    /// @param _amount amount of HUM to lock
    /// @param _lockDays number of days to lock the _amount of HUM for
    /// @return veHumToMint the amount of veHUM minted by the lock
    function lockHum(uint256 _amount, uint256 _lockDays)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 veHumToMint)
    {
        require(_amount > 0, 'amount to lock cannot be zero');
        require(lockedPositions[msg.sender].humLocked == 0, 'user already has a lock, call addHumToLock');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        // validate lock days
        require(_lockDays >= uint256(minLockDays) && _lockDays <= uint256(maxLockDays), 'lock days is invalid');

        // calculate veHUM to mint and unlock time
        veHumToMint = _expectedVeHumAmount(_amount, _lockDays * 1 minutes);
        uint256 unlockTime = block.timestamp + 1 minutes * _lockDays;

        // validate that cap is respected
        require(veHumToMint <= _amount * maxLockCap, 'lock cap is not respected');

        // check type safety
        require(unlockTime < type(uint128).max, 'overflow');
        require(_amount < type(uint128).max, 'overflow');
        require(veHumToMint < type(uint128).max, 'overflow');

        // Request Hum from user
        hum.transferFrom(msg.sender, address(this), _amount);

        lockedPositions[msg.sender] = LockedPosition(
            uint128(block.timestamp),
            uint128(unlockTime),
            uint128(_amount),
            uint128(veHumToMint)
        );

        totalLockedHum += _amount;

        _mint(msg.sender, veHumToMint);
        _claim(msg.sender);

        emit Lock(msg.sender, unlockTime, _amount, veHumToMint);

        return veHumToMint;
    }

    /// @notice adds Hum to current lock
    /// @param _amount the amount of hum to add to lock
    /// @return veHumToMint the amount of veHUM generated by adding to the lock
    function addHumToLock(uint256 _amount) external override nonReentrant whenNotPaused returns (uint256 veHumToMint) {
        require(_amount > 0, 'amount to add to lock cannot be zero');
        LockedPosition memory position = lockedPositions[msg.sender];
        require(position.humLocked > 0, 'user doesnt have a lock, call lockHum');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        require(position.unlockTime > block.timestamp, 'cannot add to a finished lock, please extend lock');

        // timeLeftInLock > 0
        uint256 timeLeftInLock = position.unlockTime - block.timestamp;

        veHumToMint = _expectedVeHumAmount(_amount, timeLeftInLock);

        // validate that cap is respected
        require(
            veHumToMint + position.veHumAmount <= (_amount + position.humLocked) * maxLockCap,
            'lock cap is not respected'
        );

        // check type safety
        require(_amount + position.humLocked < type(uint128).max, 'overflow');
        require(position.veHumAmount + veHumToMint < type(uint128).max, 'overflow');

        // Request Hum from user
        hum.transferFrom(msg.sender, address(this), _amount);

        lockedPositions[msg.sender].humLocked += uint128(_amount);
        lockedPositions[msg.sender].veHumAmount += uint128(veHumToMint);

        totalLockedHum += _amount;

        _mint(msg.sender, veHumToMint);
        _claim(msg.sender);

        emit AddToLock(msg.sender, _amount, veHumToMint);

        return veHumToMint;
    }

    /// @notice Extends curent lock by days. The total amount of veHUM generated is caculated based on the period
    /// between `initialLockTime` and the new `unlockPeriod`
    /// @dev the lock extends the duration taking into account `unlockTime` as reference. If current position is already unlockable, it will extend the position taking into consideration the registered unlock time, and not the block's timestamp.
    /// @param _daysToExtend amount of additional days to lock the position
    /// @return veHumToMint amount of veHUM generated by extension
    function extendLock(uint256 _daysToExtend)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 veHumToMint)
    {
        require(_daysToExtend >= uint256(minLockDays), 'extend: days are invalid');

        LockedPosition memory position = lockedPositions[msg.sender];

        require(position.humLocked > 0, 'extend: no hum locked');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        uint256 newUnlockTime = position.unlockTime + _daysToExtend * 1 minutes;
        require(newUnlockTime - position.initialLockTime <= uint256(maxLockDays * 1 minutes), 'extend: too much days');

        // calculate amount of veHUM to mint for the extended days
        // distributive property of `_expectedVeHumAmount` is assumed
        veHumToMint = _expectedVeHumAmount(position.humLocked, _daysToExtend * 1 minutes);

        uint256 _maxCap = maxLockCap;
        // max user veHum balance in case the extension was about to exceed lock
        if (veHumToMint + position.veHumAmount > position.humLocked * _maxCap) {
            // mint enough to max the position
            veHumToMint = position.humLocked * _maxCap - position.veHumAmount;
        }

        // validate type safety
        require(newUnlockTime < type(uint128).max, 'overflow');
        require(veHumToMint + position.veHumAmount < type(uint128).max, 'overflow');

        // assign new unlock time and veHUM amount
        lockedPositions[msg.sender].unlockTime = uint128(newUnlockTime);
        lockedPositions[msg.sender].veHumAmount = position.veHumAmount + uint128(veHumToMint);

        _mint(msg.sender, veHumToMint);
        _claim(msg.sender);

        emit ExtendLock(msg.sender, _daysToExtend, newUnlockTime, veHumToMint);

        return veHumToMint;
    }

    /// @notice unlocks all HUM for a user
    //// Lock needs to expire before unlock
    /// @return the amount of HUM recovered by the unlock
    function unlockHum() external override nonReentrant whenNotPaused returns (uint256) {
        LockedPosition memory position = lockedPositions[msg.sender];
        require(position.humLocked > 0, 'no hum locked');
        require(position.unlockTime <= block.timestamp, 'not yet');
        uint256 humToUnlock = position.humLocked;
        uint256 veHumToBurn = position.veHumAmount;

        // delete the lock position from mapping
        delete lockedPositions[msg.sender];

        totalLockedHum -= humToUnlock;

        // burn corresponding veHUM
        _burn(msg.sender, veHumToBurn);

        // reset rewarder
        if (address(rewarder) != address(0)) {
            rewarder.onHumReward(msg.sender, balanceOf(msg.sender));
        }

        // transfer the hum to the user
        hum.transfer(msg.sender, humToUnlock);

        emit Unlock(msg.sender, position.unlockTime, humToUnlock, veHumToBurn);

        return humToUnlock;
    }

    /// @notice deposits HUM into contract
    /// @param _amount the amount of hum to deposit
    function deposit(uint256 _amount) external override nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to deposit cannot be zero');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        if (isUserStaking(msg.sender)) {
            // if user exists, first, claim his veHUM
            _claim(msg.sender);
            // then, increment his holdings
            users[msg.sender].amount += _amount;
        } else {
            // add new user to mapping
            users[msg.sender].lastRelease = block.timestamp;
            users[msg.sender].amount = _amount;
        }

        // Request Hum from user
        // SafeERC20 is not needed as HUM will revert if transfer fails
        hum.transferFrom(msg.sender, address(this), _amount);

        // emit event
        emit Staked(msg.sender, _amount);
    }

    /// @notice asserts addres in param is not a smart contract.
    /// @notice if it is a smart contract, check that it is whitelisted
    /// @param _addr the address to check
    function _assertNotContract(address _addr) private view {
        if (_addr != tx.origin) {
            require(
                address(whitelist) != address(0) && whitelist.check(_addr),
                'Smart contract depositors not allowed'
            );
        }
    }

    /// @notice claims accumulated veHUM
    function claim() external override nonReentrant whenNotPaused {
        require(isUserStaking(msg.sender) || isUserLocking(msg.sender), 'user has no stake or lock');
        _claim(msg.sender);
    }

    /// @dev private claim function
    /// @param _addr the address of the user to claim from
    function _claim(address _addr) private {
        // claim accrued veHum for staked positions only
        if (isUserStaking(_addr)) {
            uint256 amount = _claimable(_addr);

            UserInfo storage user = users[_addr];

            // update last release time
            user.lastRelease = block.timestamp;

            if (amount > 0) {
                emit Claimed(_addr, amount);
                _mint(_addr, amount);
            }
        }

        // payout extra rewards, if any, based on veHum balance
        if (address(rewarder) != address(0)) {
            rewarder.onHumReward(_addr, balanceOf(_addr));
        }
    }

    /// @notice returns amount of veHUM that has been generated by staking (including those from NFT)
    /// @param _addr the address to check
    function veHumGeneratedByStake(address _addr) public view returns (uint256) {
        return balanceOf(_addr) - lockedPositions[_addr].veHumAmount;
    }

    /// @notice returns amount of veHUM that has been generated by staking
    /// @param _addr the address to check
    function veHumGeneratedByLock(address _addr) public view returns (uint256) {
        return lockedPositions[_addr].veHumAmount;
    }

    /// @notice Calculate the amount of veHUM that can be claimed by user
    /// @param _addr the address to check
    /// @return amount of veHUM that can be claimed by user
    function claimable(address _addr) external view returns (uint256 amount) {
        require(_addr != address(0), 'zero address');
        amount= _claimable(_addr);
    }

    /// @notice Calculate the amount of veHUM that can be claimed by user
    /// @dev private claimable function
    /// @param _addr the address to check
    /// @return amount of veHUM that can be claimed by user
    function _claimable(address _addr) private view returns (uint256 amount) {
        UserInfo storage user = users[_addr];

        // get seconds elapsed since last claim
        uint256 secondsElapsed = block.timestamp - user.lastRelease;

        // calculate pending amount
        // Math.mwmul used to multiply wad numbers
        uint256 pending = Math.wmul(user.amount, secondsElapsed * generationRate);

        // get user's veHUM balance
        uint256 userVeHumBalance = veHumGeneratedByStake(_addr);

        // user veHUM balance cannot go above user.amount * maxStakeCap
        uint256 maxVeHumCap = user.amount * maxStakeCap;      

        // first, check that user hasn't reached the max limit yet
        if (userVeHumBalance < maxVeHumCap) {
            // amount of veHUM to reach max cap
            uint256 amountToCap = maxVeHumCap - userVeHumBalance;

            // then, check if pending amount will make user balance overpass maximum amount
            if (pending >= amountToCap) {
                amount = amountToCap;
            } else {
                amount = pending;
            }
        } else {
            amount = 0;
        }
    }

    /// @notice withdraws staked hum
    /// @param _amount the amount of hum to unstake
    /// Note Beware! you will loose all of your veHUM minted from staking if you unstake any amount of hum!
    /// Besides, if you withdraw all HUM and you have staked NFT, it will be unstaked
    function withdraw(uint256 _amount) external override nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to withdraw cannot be zero');
        require(users[msg.sender].amount >= _amount, 'not enough balance');

        // reset last Release timestamp
        users[msg.sender].lastRelease = block.timestamp;

        // update his balance before burning or sending back hum
        users[msg.sender].amount -= _amount;

        // get user veHUM balance that must be burned
        uint256 userVeHumBalance = veHumGeneratedByStake(msg.sender);

        _burn(msg.sender, userVeHumBalance);

        // reset rewarder
        if (address(rewarder) != address(0)) {
            rewarder.onHumReward(msg.sender, balanceOf(msg.sender));
        }

        // send back the staked hum
        // SafeERC20 is not needed as HUM will revert if transfer fails
        hum.transfer(msg.sender, _amount);

        // emit event
        emit Unstaked(msg.sender, _amount);
    }

    /// @notice hook called after token operation mint/burn
    /// @dev updates masterHummus
    /// @param _account the account being affected
    /// @param _newBalance the newVeHumBalance of the user
    function _afterTokenOperation(address _account, uint256 _newBalance) internal override {
        _verifyVoteIsEnough(_account);
        masterHummus.updateFactor(_account, _newBalance);
    }

    /// @notice This function is called when users stake NFTs
    function stakeNft(uint256 _tokenId) external override nonReentrant whenNotPaused {
        require(isUserStaking(msg.sender), 'user has no stake');

        nft.transferFrom(msg.sender, address(this), _tokenId);

        // first, claim his veHUM
        _claim(msg.sender);

        // user has previously staked some NFT, try to unstake it
        if (users[msg.sender].stakedNftId != 0) {
            _unstakeNft(msg.sender);
        }

        users[msg.sender].stakedNftId = _tokenId + 1; // add offset

        if (msg.sender != tx.origin) {
            lastBlockToStakeNftByContract[msg.sender] = block.number;
        }

        emit StakedNft(msg.sender, _tokenId);
    }

    /// @notice unstakes current user nft
    function unstakeNft() external override nonReentrant whenNotPaused {
        // first, claim his veHUM
        // one should always has deposited if he has staked NFT
        _claim(msg.sender);

        _unstakeNft(msg.sender);
    }

    /// @notice private function used to unstake nft
    /// @param _addr the address of the nft owner
    function _unstakeNft(address _addr) private {
        uint256 nftId = users[_addr].stakedNftId;
        require(nftId > 0, 'No NFT is staked');
        --nftId; // remove offset

        nft.transferFrom(address(this), _addr, nftId);

        users[_addr].stakedNftId = 0;

        emit UnstakedNft(_addr, nftId);
    }

    /// @notice gets id of the staked nft
    /// @param _addr the addres of the nft staker
    /// @return id of the staked nft by _addr user
    /// if the user haven't stake any nft, tx reverts
    function getStakedNft(address _addr) external view returns (uint256) {
        uint256 nftId = users[_addr].stakedNftId;
        require(nftId > 0, 'not staking NFT');
        return nftId - 1; // remove offset
    }

    /// @notice get votes for veHUM
    /// @dev votes should only count if account has > threshold% of current cap reached
    /// @dev invVoteThreshold = (1/threshold%)*100
    /// @param _addr the addres of the nft staker
    /// @return the valid votes
    function getVotes(address _addr) external view virtual override returns (uint256) {
        uint256 veHumBalance = balanceOf(_addr);

        // check that user has more than voting treshold of maxStakeCap and maxLockCap
        if (
            veHumBalance * invVoteThreshold >
            users[_addr].amount * maxStakeCap + lockedPositions[_addr].humLocked * maxLockCap
        ) {
            return veHumBalance;
        } else {
            return 0;
        }
    }

    function vote(address _user, int256 _voteDelta) external override {
        _onlyVoter();

        if (_voteDelta >= 0) {
            usedVote[_user] += uint256(_voteDelta);
            _verifyVoteIsEnough(_user);
        } else {
            // reverts if usedVote[_user] < -_voteDelta
            usedVote[_user] -= uint256(-_voteDelta);
        }
    }
}
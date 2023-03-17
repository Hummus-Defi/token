// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './VeERC20Upgradeable.sol';
import './Whitelist.sol';
import './interfaces/IMasterPlatypus.sol';
import './libraries/Math.sol';
import './libraries/SafeOwnableUpgradeable.sol';
import './interfaces/IVePtpV3.sol';
import './interfaces/IPlatypusNFT.sol';

interface IVe {
    function vote(address _user, int256 _voteDelta) external;
}

/// @title VePtpV3
/// @notice Platypus Venom: the staking contract for PTP, as well as the token used for governance.
/// Note Venom does not seem to hurt the Platypus, it only makes it stronger.
/// Allows depositing/withdraw of ptp and staking/unstaking ERC721.
/// Here are the rules of the game:
/// If you stake ptp, you generate vePtp at the current `generationRate` until you reach `maxStakeCap`
/// If you unstake any amount of ptp, you loose all of your vePtp.
/// Note that it's ownable and the owner wields tremendous power. The ownership
/// will be transferred to a governance smart contract once Platypus is sufficiently
/// distributed and the community can show to govern itself.
/// VePtpV3 updates
/// - User can lock PTP and instantly mint vePTP.
/// - API change:
///   - maxCap => maxStakeCap
///   - isUser => isUserStaking
contract VePtpV3 is
    Initializable,
    SafeOwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    VeERC20Upgradeable,
    IVePtpV3,
    IVe
{
    // Staking user info
    struct UserInfo {
        uint256 amount; // ptp staked by user
        uint256 lastRelease; // time of last vePtp claim or first deposit if user has not claimed yet
        // the id of the currently staked nft
        // important note: the id is offset by +1 to handle tokenID = 0
        // stakedNftId = 0 (default value) means that no NFT is staked
        uint256 stakedNftId;
    }

    // Locking user info
    struct LockedPosition {
        uint128 initialLockTime;
        uint128 unlockTime;
        uint128 ptpLocked;
        uint128 vePtpAmount;
    }

    /// @notice the ptp token
    IERC20 public ptp;

    /// @notice the masterPlatypus contract
    IMasterPlatypus public masterPlatypus;

    /// @notice the NFT contract
    IPlatypusNFT public nft;

    /// @notice max vePtp to staked ptp ratio
    /// Note if user has 10 ptp staked, they can only have a max of 10 * maxStakeCap vePtp in balance
    uint256 public maxStakeCap;

    /// @notice the rate of vePtp generated per second, per ptp staked
    uint256 public generationRate;

    /// @notice invVvoteThreshold threshold.
    /// @notice voteThreshold is the tercentage of cap from which votes starts to count for governance proposals.
    /// @dev inverse of the threshold to apply.
    /// Example: th = 5% => (1/5) * 100 => invVoteThreshold = 20
    /// Example 2: th = 3.03% => (1/3.03) * 100 => invVoteThreshold = 33
    /// Formula is invVoteThreshold = (1 / th) * 100
    uint256 public invVoteThreshold;

    /// @notice whitelist wallet checker
    /// @dev contract addresses are by default unable to stake ptp, they must be previously whitelisted to stake ptp
    Whitelist public whitelist;

    /// @notice user info mapping
    // note Staking user info
    mapping(address => UserInfo) public users;

    uint256 public maxNftLevel;
    uint256 public xpEnableTime;

    // reserve more space for extensibility
    uint256[100] public xpRequiredForLevelUp;

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

    /// @notice Locked PTP user info
    mapping(address => LockedPosition) public lockedPositions;

    /// @notice total amount of ptp locked
    uint256 public totalLockedPtp;

    /// @notice events describing staking, unstaking and claiming
    event Staked(address indexed user, uint256 indexed amount);
    event Unstaked(address indexed user, uint256 indexed amount);
    event Claimed(address indexed user, uint256 indexed amount);

    /// @notice events describing NFT staking and unstaking
    event StakedNft(address indexed user, uint256 indexed nftId);
    event UnstakedNft(address indexed user, uint256 indexed nftId);

    /// @notice events describing locking mechanics
    event Lock(address indexed user, uint256 unlockTime, uint256 amount, uint256 vePtpToMint);
    event ExtendLock(address indexed user, uint256 daysToExtend, uint256 unlockTime, uint256 vePtpToMint);
    event AddToLock(address indexed user, uint256 amountAdded, uint256 vePtpToMint);
    event Unlock(address indexed user, uint256 unlockTime, uint256 amount, uint256 vePtpToBurn);

    function initialize(
        IERC20 _ptp,
        IMasterPlatypus _masterPlatypus,
        IPlatypusNFT _nft
    ) public initializer {
        require(address(_masterPlatypus) != address(0), 'zero address');
        require(address(_ptp) != address(0), 'zero address');
        require(address(_nft) != address(0), 'zero address');

        // Initialize vePTP
        __ERC20_init('Platypus Venom', 'vePTP');
        __Ownable_init();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();

        // set generationRate (vePtp per sec per ptp staked)
        generationRate = 3888888888888;

        // set maxStakeCap
        maxStakeCap = 100;

        // set inv vote threshold
        // invVoteThreshold = 20 => th = 5
        invVoteThreshold = 20;

        // set master platypus
        masterPlatypus = _masterPlatypus;

        // set ptp
        ptp = _ptp;

        // set nft, can be zero address at first
        nft = _nft;

        initializeNft();
        initializeLockDays();
    }

    function _verifyVoteIsEnough(address _user) internal view {
        require(balanceOf(_user) >= usedVote[_user], 'VePtp: not enough vote');
    }

    function _onlyVoter() internal view {
        require(msg.sender == voter, 'VePtp: caller is not voter');
    }

    function initializeNft() public onlyOwner {
        maxNftLevel = 1; // to enable leveling, call setMaxNftLevel
        xpRequiredForLevelUp = [uint256(0), 3000 ether, 30000 ether, 300000 ether, 3000000 ether];
    }

    function initializeLockDays() public onlyOwner {
        minLockDays = 7; // 1 week
        maxLockDays = 357; // 357/(365/12) ~ 11.7 months
        maxLockCap = 120; // < 12 month max lock

        // ~18 month max stake, can set separately
        // maxStakeCap = 180;
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
    /// @param _masterPlatypus the new masterPlatypus address
    function setMasterPlatypus(IMasterPlatypus _masterPlatypus) external onlyOwner {
        require(address(_masterPlatypus) != address(0), 'zero address');
        masterPlatypus = _masterPlatypus;
    }

    /// @notice sets NFT contract address
    /// @param _nft the new NFT contract address
    function setNftAddress(IPlatypusNFT _nft) external onlyOwner {
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

    /// @notice sets setMaxNftLevel, the first time this function is called, leveling will be enabled
    /// @param _maxNftLevel the new var
    function setMaxNftLevel(uint8 _maxNftLevel) external onlyOwner {
        maxNftLevel = _maxNftLevel;

        if (xpEnableTime == 0) {
            // enable users to accumulate timestamp the first time this function is invoked
            xpEnableTime = block.timestamp;
        }
    }

    /// @notice checks wether user _addr has ptp staked
    /// @param _addr the user address to check
    /// @return true if the user has ptp in stake, false otherwise
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

    /// @notice returns staked amount of ptp for user
    /// @param _addr the user address to check
    /// @return staked amount of ptp
    function getStakedPtp(address _addr) external view override returns (uint256) {
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

    /// @notice returns expected vePTP amount to be minted given amount and number of days to lock
    function _expectedVePtpAmount(uint256 _amount, uint256 _lockSeconds) private view returns (uint256) {
        return Math.wmul(_amount, _lockSeconds * generationRate);
    }

    function quoteExpectedVePtpAmount(uint256 _amount, uint256 _lockDays) external view returns (uint256) {
        return _expectedVePtpAmount(_amount, _lockDays * 1 days);
    }

    /// @notice locks PTP in the contract, immediately minting vePTP
    /// @param _amount amount of PTP to lock
    /// @param _lockDays number of days to lock the _amount of PTP for
    /// @return vePtpToMint the amount of vePTP minted by the lock
    function lockPtp(uint256 _amount, uint256 _lockDays)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 vePtpToMint)
    {
        require(_amount > 0, 'amount to lock cannot be zero');
        require(lockedPositions[msg.sender].ptpLocked == 0, 'user already has a lock, call addPtpToLock');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        // validate lock days
        require(_lockDays >= uint256(minLockDays) && _lockDays <= uint256(maxLockDays), 'lock days is invalid');

        // calculate vePTP to mint and unlock time
        vePtpToMint = _expectedVePtpAmount(_amount, _lockDays * 1 days);
        uint256 unlockTime = block.timestamp + 1 days * _lockDays;

        // validate that cap is respected
        require(vePtpToMint <= _amount * maxLockCap, 'lock cap is not respected');

        // check type safety
        require(unlockTime < type(uint128).max, 'overflow');
        require(_amount < type(uint128).max, 'overflow');
        require(vePtpToMint < type(uint128).max, 'overflow');

        // Request Ptp from user
        ptp.transferFrom(msg.sender, address(this), _amount);

        lockedPositions[msg.sender] = LockedPosition(
            uint128(block.timestamp),
            uint128(unlockTime),
            uint128(_amount),
            uint128(vePtpToMint)
        );

        totalLockedPtp += _amount;

        _mint(msg.sender, vePtpToMint);

        emit Lock(msg.sender, unlockTime, _amount, vePtpToMint);

        return vePtpToMint;
    }

    /// @notice adds Ptp to current lock
    /// @param _amount the amount of ptp to add to lock
    /// @return vePtpToMint the amount of vePTP generated by adding to the lock
    function addPtpToLock(uint256 _amount) external override nonReentrant whenNotPaused returns (uint256 vePtpToMint) {
        require(_amount > 0, 'amount to add to lock cannot be zero');
        LockedPosition memory position = lockedPositions[msg.sender];
        require(position.ptpLocked > 0, 'user doesnt have a lock, call lockPtp');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        require(position.unlockTime > block.timestamp, 'cannot add to a finished lock, please extend lock');

        // timeLeftInLock > 0
        uint256 timeLeftInLock = position.unlockTime - block.timestamp;

        vePtpToMint = _expectedVePtpAmount(_amount, timeLeftInLock);

        // validate that cap is respected
        require(
            vePtpToMint + position.vePtpAmount <= (_amount + position.ptpLocked) * maxLockCap,
            'lock cap is not respected'
        );

        // check type safety
        require(_amount + position.ptpLocked < type(uint128).max, 'overflow');
        require(position.vePtpAmount + vePtpToMint < type(uint128).max, 'overflow');

        // Request Ptp from user
        ptp.transferFrom(msg.sender, address(this), _amount);

        lockedPositions[msg.sender].ptpLocked += uint128(_amount);
        lockedPositions[msg.sender].vePtpAmount += uint128(vePtpToMint);

        totalLockedPtp += _amount;

        _mint(msg.sender, vePtpToMint);
        emit AddToLock(msg.sender, _amount, vePtpToMint);

        return vePtpToMint;
    }

    /// @notice Extends curent lock by days. The total amount of vePTP generated is caculated based on the period
    /// between `initialLockTime` and the new `unlockPeriod`
    /// @dev the lock extends the duration taking into account `unlockTime` as reference. If current position is already unlockable, it will extend the position taking into consideration the registered unlock time, and not the block's timestamp.
    /// @param _daysToExtend amount of additional days to lock the position
    /// @return vePtpToMint amount of vePTP generated by extension
    function extendLock(uint256 _daysToExtend)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 vePtpToMint)
    {
        require(_daysToExtend >= uint256(minLockDays), 'extend: days are invalid');

        LockedPosition memory position = lockedPositions[msg.sender];

        require(position.ptpLocked > 0, 'extend: no ptp locked');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        uint256 newUnlockTime = position.unlockTime + _daysToExtend * 1 days;
        require(newUnlockTime - position.initialLockTime <= uint256(maxLockDays * 1 days), 'extend: too much days');

        // calculate amount of vePTP to mint for the extended days
        // distributive property of `_expectedVePtpAmount` is assumed
        vePtpToMint = _expectedVePtpAmount(position.ptpLocked, _daysToExtend * 1 days);

        uint256 _maxCap = maxLockCap;
        // max user vePtp balance in case the extension was about to exceed lock
        if (vePtpToMint + position.vePtpAmount > position.ptpLocked * _maxCap) {
            // mint enough to max the position
            vePtpToMint = position.ptpLocked * _maxCap - position.vePtpAmount;
        }

        // validate type safety
        require(newUnlockTime < type(uint128).max, 'overflow');
        require(vePtpToMint + position.vePtpAmount < type(uint128).max, 'overflow');

        // assign new unlock time and vePTP amount
        lockedPositions[msg.sender].unlockTime = uint128(newUnlockTime);
        lockedPositions[msg.sender].vePtpAmount = position.vePtpAmount + uint128(vePtpToMint);

        _mint(msg.sender, vePtpToMint);

        emit ExtendLock(msg.sender, _daysToExtend, newUnlockTime, vePtpToMint);

        return vePtpToMint;
    }

    /// @notice unlocks all PTP for a user
    //// Lock needs to expire before unlock
    /// @return the amount of PTP recovered by the unlock
    function unlockPtp() external override nonReentrant whenNotPaused returns (uint256) {
        LockedPosition memory position = lockedPositions[msg.sender];
        require(position.ptpLocked > 0, 'no ptp locked');
        require(position.unlockTime <= block.timestamp, 'not yet');
        uint256 ptpToUnlock = position.ptpLocked;
        uint256 vePtpToBurn = position.vePtpAmount;

        // delete the lock position from mapping
        delete lockedPositions[msg.sender];

        totalLockedPtp -= ptpToUnlock;

        // burn corresponding vePTP
        _burn(msg.sender, vePtpToBurn);

        // transfer the ptp to the user
        ptp.transfer(msg.sender, ptpToUnlock);

        emit Unlock(msg.sender, position.unlockTime, ptpToUnlock, vePtpToBurn);

        return ptpToUnlock;
    }

    /// @notice deposits PTP into contract
    /// @param _amount the amount of ptp to deposit
    function deposit(uint256 _amount) external override nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to deposit cannot be zero');

        // assert call is not coming from a smart contract
        // unless it is whitelisted
        _assertNotContract(msg.sender);

        if (isUserStaking(msg.sender)) {
            // if user exists, first, claim his vePTP
            _claim(msg.sender);
            // then, increment his holdings
            users[msg.sender].amount += _amount;
        } else {
            // add new user to mapping
            users[msg.sender].lastRelease = block.timestamp;
            users[msg.sender].amount = _amount;
        }

        // Request Ptp from user
        // SafeERC20 is not needed as PTP will revert if transfer fails
        ptp.transferFrom(msg.sender, address(this), _amount);

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

    /// @notice claims accumulated vePTP
    function claim() external override nonReentrant whenNotPaused {
        require(isUserStaking(msg.sender), 'user has no stake');
        _claim(msg.sender);
    }

    /// @dev private claim function
    /// @param _addr the address of the user to claim from
    function _claim(address _addr) private {
        uint256 amount;
        uint256 xp;
        (amount, xp) = _claimable(_addr);

        UserInfo storage user = users[_addr];

        // update last release time
        user.lastRelease = block.timestamp;

        if (amount > 0) {
            emit Claimed(_addr, amount);
            _mint(_addr, amount);
        }

        if (xp > 0) {
            uint256 nftId = user.stakedNftId;

            // if nftId > 0, user has nft staked
            if (nftId > 0) {
                --nftId; // remove offset

                // level is already validated in _claimable()
                nft.growXp(nftId, xp);
            }
        }
    }

    /// @notice returns amount of vePTP that has been generated by staking (including those from NFT)
    /// @param _addr the address to check
    function vePtpGeneratedByStake(address _addr) public view returns (uint256) {
        return balanceOf(_addr) - lockedPositions[_addr].vePtpAmount;
    }

    /// @notice returns amount of vePTP that has been generated by staking
    /// @param _addr the address to check
    function vePtpGeneratedByLock(address _addr) public view returns (uint256) {
        return lockedPositions[_addr].vePtpAmount;
    }

    /// @notice Calculate the amount of vePTP that can be claimed by user
    /// @param _addr the address to check
    /// @return amount of vePTP that can be claimed by user
    function claimable(address _addr) external view returns (uint256 amount) {
        require(_addr != address(0), 'zero address');
        (amount, ) = _claimable(_addr);
    }

    /// @notice Calculate the amount of vePTP that can be claimed by user
    /// @param _addr the address to check
    /// @return amount of vePTP that can be claimed by user
    /// @return xp potential xp for NFT staked
    function claimableWithXp(address _addr) external view returns (uint256 amount, uint256 xp) {
        require(_addr != address(0), 'zero address');
        return _claimable(_addr);
    }

    /// @notice Calculate the amount of vePTP that can be claimed by user
    /// @dev private claimable function
    /// @param _addr the address to check
    /// @return amount of vePTP that can be claimed by user
    /// @return xp potential xp for NFT staked
    function _claimable(address _addr) private view returns (uint256 amount, uint256 xp) {
        UserInfo storage user = users[_addr];

        // get seconds elapsed since last claim
        uint256 secondsElapsed = block.timestamp - user.lastRelease;

        // calculate pending amount
        // Math.mwmul used to multiply wad numbers
        uint256 pending = Math.wmul(user.amount, secondsElapsed * generationRate);

        // get user's vePTP balance
        uint256 userVePtpBalance = vePtpGeneratedByStake(_addr);

        // user vePTP balance cannot go above user.amount * maxStakeCap
        uint256 maxVePtpCap = user.amount * maxStakeCap;

        // handle nft effects
        uint256 nftId = user.stakedNftId;
        // if nftId > 0, user has nft staked
        if (nftId > 0) {
            --nftId; // remove offset
            uint32 speedo;
            uint32 pudgy;
            uint32 diligent;
            uint32 gifted;
            (speedo, pudgy, diligent, gifted, ) = nft.getPlatypusDetails(nftId);

            if (speedo > 0) {
                // Speedo: x% faster vePTP generation
                pending = (pending * (100 + speedo)) / 100;
            }
            if (diligent > 0) {
                // Diligent: +D vePTP every hour (subject to cap)
                pending += ((uint256(diligent) * (10**decimals())) * secondsElapsed) / 1 hours;
            }
            if (pudgy > 0) {
                // Pudgy: x% higher vePTP cap
                maxVePtpCap = (maxVePtpCap * (100 + pudgy)) / 100;
            }
            if (gifted > 0) {
                // Gifted: +D vePTP regardless of PTP staked
                // The cap should also increase D
                maxVePtpCap += uint256(gifted) * (10**decimals());
            }

            uint256 level = nft.getPlatypusLevel(nftId);
            if (level < maxNftLevel) {
                // Accumulate XP only after leveling is enabled
                if (user.lastRelease >= xpEnableTime) {
                    xp = pending;
                } else {
                    xp = (pending * (block.timestamp - xpEnableTime)) / (block.timestamp - user.lastRelease);
                }
                uint256 currentXp = nft.getPlatypusXp(nftId);

                if (xp + currentXp > xpRequiredForLevelUp[level]) {
                    xp = xpRequiredForLevelUp[level] - currentXp;
                }
            }
        }

        // first, check that user hasn't reached the max limit yet
        if (userVePtpBalance < maxVePtpCap) {
            // amount of vePTP to reach max cap
            uint256 amountToCap = maxVePtpCap - userVePtpBalance;

            // then, check if pending amount will make user balance overpass maximum amount
            if (pending >= amountToCap) {
                amount = amountToCap;
            } else {
                amount = pending;
            }
        } else {
            amount = 0;
        }
        // Note: maxVePtpCap doesn't affect growing XP
    }

    /// @notice withdraws staked ptp
    /// @param _amount the amount of ptp to unstake
    /// Note Beware! you will loose all of your vePTP minted from staking if you unstake any amount of ptp!
    /// Besides, if you withdraw all PTP and you have staked NFT, it will be unstaked
    function withdraw(uint256 _amount) external override nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to withdraw cannot be zero');
        require(users[msg.sender].amount >= _amount, 'not enough balance');

        uint256 nftId = users[msg.sender].stakedNftId;
        if (nftId > 0) {
            // claim to grow XP
            _claim(msg.sender);
        } else {
            users[msg.sender].lastRelease = block.timestamp;
        }

        // get user vePTP balance that must be burned before updating his balance
        uint256 valueToBurn = _vePtpBurnedOnWithdraw(msg.sender, _amount);

        // update his balance before burning or sending back ptp
        users[msg.sender].amount -= _amount;

        _burn(msg.sender, valueToBurn);

        // unstake NFT if all PTP is unstaked
        if (users[msg.sender].amount == 0 && users[msg.sender].stakedNftId != 0) {
            _unstakeNft(msg.sender);
        }

        // send back the staked ptp
        // SafeERC20 is not needed as PTP will revert if transfer fails
        ptp.transfer(msg.sender, _amount);

        // emit event
        emit Unstaked(msg.sender, _amount);
    }

    /// Calculate the amount of vePTP that will be burned when PTP is withdrawn
    /// @param _amount the amount of ptp to unstake
    /// @return the amount of vePTP that will be burned
    function vePtpBurnedOnWithdraw(address _addr, uint256 _amount) external view returns (uint256) {
        return _vePtpBurnedOnWithdraw(_addr, _amount);
    }

    /// Private function to calculate the amount of vePTP that will be burned when PTP is withdrawn
    /// Does NOT burn amount generated by locking upon withdrawal of staked PTP.
    /// @param _amount the amount of ptp to unstake
    /// @return the amount of vePTP that will be burned
    function _vePtpBurnedOnWithdraw(address _addr, uint256 _amount) private view returns (uint256) {
        require(_amount <= users[_addr].amount, 'not enough ptp');
        uint256 vePtpBalance = vePtpGeneratedByStake(_addr);
        uint256 nftId = users[_addr].stakedNftId;

        if (nftId == 0) {
            // user doesn't have nft staked
            return vePtpBalance;
        } else {
            --nftId; // remove offset
            (, , , uint32 gifted, uint32 hibernate) = nft.getPlatypusDetails(nftId);

            if (gifted > 0) {
                // Gifted: don't burn vePtp given by Gifted
                vePtpBalance -= uint256(gifted) * (10**decimals());
            }

            // retain some vePTP using nft
            // if it is a smart contract, check lastBlockToStakeNftByContract is not the current block
            // in case of flash loan attack
            if (
                hibernate > 0 && (msg.sender == tx.origin || lastBlockToStakeNftByContract[msg.sender] != block.number)
            ) {
                // Hibernate: Retain x% vePTP of cap upon unstaking
                return
                    vePtpBalance -
                    (vePtpBalance * hibernate * (users[_addr].amount - _amount)) /
                    users[_addr].amount /
                    100;
            } else {
                return vePtpBalance;
            }
        }
    }

    /// @notice hook called after token operation mint/burn
    /// @dev updates masterPlatypus
    /// @param _account the account being affected
    /// @param _newBalance the newVePtpBalance of the user
    function _afterTokenOperation(address _account, uint256 _newBalance) internal override {
        _verifyVoteIsEnough(_account);
        masterPlatypus.updateFactor(_account, _newBalance);
    }

    /// @notice This function is called when users stake NFTs
    function stakeNft(uint256 _tokenId) external override nonReentrant whenNotPaused {
        require(isUserStaking(msg.sender), 'user has no stake');

        nft.transferFrom(msg.sender, address(this), _tokenId);

        // first, claim his vePTP
        _claim(msg.sender);

        // user has previously staked some NFT, try to unstake it
        if (users[msg.sender].stakedNftId != 0) {
            _unstakeNft(msg.sender);
        }

        users[msg.sender].stakedNftId = _tokenId + 1; // add offset

        if (msg.sender != tx.origin) {
            lastBlockToStakeNftByContract[msg.sender] = block.number;
        }

        _afterNftStake(msg.sender, _tokenId);
        emit StakedNft(msg.sender, _tokenId);
    }

    function _afterNftStake(address _addr, uint256 nftId) private {
        uint32 gifted;
        (, , , gifted, ) = nft.getPlatypusDetails(nftId);
        // mint vePTP using nft
        if (gifted > 0) {
            // Gifted: +D vePTP regardless of PTP staked
            _mint(_addr, uint256(gifted) * (10**decimals()));
        }
    }

    /// @notice unstakes current user nft
    function unstakeNft() external override nonReentrant whenNotPaused {
        // first, claim his vePTP
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

        _afterNftUnstake(_addr, nftId);
        emit UnstakedNft(_addr, nftId);
    }

    function _afterNftUnstake(address _addr, uint256 nftId) private {
        uint32 gifted;
        (, , , gifted, ) = nft.getPlatypusDetails(nftId);
        // burn vePTP minted by nft
        if (gifted > 0) {
            // Gifted: +D vePTP regardless of PTP staked
            _burn(_addr, uint256(gifted) * (10**decimals()));
        }
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

    /// @notice level up the staked NFT
    /// @param platypusToBurn token IDs of platypuses to burn
    function levelUp(uint256[] calldata platypusToBurn) external override nonReentrant whenNotPaused {
        uint256 nftId = users[msg.sender].stakedNftId;
        require(nftId > 0, 'not staking NFT');
        --nftId; // remove offset

        uint16 level = nft.getPlatypusLevel(nftId);
        require(level < maxNftLevel, 'max level reached');

        uint256 sumOfLevels;

        for (uint256 i; i < platypusToBurn.length; ++i) {
            uint256 level_ = nft.getPlatypusLevel(platypusToBurn[i]); // 1 - 5
            uint256 exp = nft.getPlatypusXp(platypusToBurn[i]);

            // only count levels which maxXp is reached;
            sumOfLevels += level_ - 1;
            if (exp >= xpRequiredForLevelUp[level_]) {
                ++sumOfLevels;
            } else {
                require(level_ > 1, 'invalid platypusToBurn');
            }
        }
        require(sumOfLevels >= level, 'vePTP: wut are you burning?');

        // claim veptp before level up
        _claim(msg.sender);

        // Remove effect from Gifted
        _afterNftUnstake(msg.sender, nftId);

        // require XP
        require(nft.getPlatypusXp(nftId) >= xpRequiredForLevelUp[level], 'vePTP: XP not enough');

        // skill acquiring
        // acquire the primary skill of a burned platypus
        {
            uint256 contributor = 0;
            if (platypusToBurn.length > 1) {
                uint256 seed = _enoughRandom();
                contributor = (seed >> 8) % platypusToBurn.length;
            }

            uint256 newAbility;
            uint256 newPower;
            (newAbility, newPower) = nft.getPrimaryAbility(platypusToBurn[contributor]);
            nft.levelUp(nftId, newAbility, newPower);
            require(nft.getPlatypusXp(nftId) == 0, 'vePTP: XP should reset');
        }

        // Re apply effect for Gifted
        _afterNftStake(msg.sender, nftId);

        // burn platypuses
        for (uint16 i = 0; i < platypusToBurn.length; ++i) {
            require(nft.ownerOf(platypusToBurn[i]) == msg.sender, 'vePTP: not owner');
            nft.burn(platypusToBurn[i]);
        }
    }

    /// @dev your sure?
    function _enoughRandom() private view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        // solhint-disable-next-line
                        block.timestamp,
                        msg.sender,
                        blockhash(block.number - 1)
                    )
                )
            );
    }

    /// @notice level down the staked NFT
    function levelDown() external override nonReentrant whenNotPaused {
        uint256 nftId = users[msg.sender].stakedNftId;
        require(nftId > 0, 'not staking NFT');
        --nftId; // remove offset

        require(nft.getPlatypusLevel(nftId) > 1, 'wut?');

        _claim(msg.sender);

        // Remove effect from Gifted
        _afterNftUnstake(msg.sender, nftId);

        nft.levelDown(nftId);

        // grow to max XP after leveling down
        uint256 maxXp = xpRequiredForLevelUp[nft.getPlatypusLevel(nftId)];
        nft.growXp(nftId, maxXp);

        // Apply effect for Gifted
        _afterNftStake(msg.sender, nftId);

        // veptp should be capped
        uint32 pudgy;
        uint32 gifted;
        (, pudgy, , gifted, ) = nft.getPlatypusDetails(nftId);
        uint256 maxVePtpCap = users[msg.sender].amount * maxStakeCap;
        maxVePtpCap = (maxVePtpCap * (100 + pudgy)) / 100 + uint256(gifted) * (10**decimals());

        if (vePtpGeneratedByStake(msg.sender) > maxVePtpCap) {
            _burn(msg.sender, vePtpGeneratedByStake(msg.sender) - maxVePtpCap);
        }
    }

    /// @notice get votes for vePTP
    /// @dev votes should only count if account has > threshold% of current cap reached
    /// @dev invVoteThreshold = (1/threshold%)*100
    /// @param _addr the addres of the nft staker
    /// @return the valid votes
    function getVotes(address _addr) external view virtual override returns (uint256) {
        uint256 vePtpBalance = balanceOf(_addr);

        uint256 nftId = users[_addr].stakedNftId;
        // if nftId > 0, user has nft staked
        if (nftId > 0) {
            --nftId; //remove offset
            uint32 gifted;
            (, , , gifted, ) = nft.getPlatypusDetails(nftId);
            // burn vePTP minted by nft
            if (gifted > 0) {
                vePtpBalance -= uint256(gifted) * (10**decimals());
            }
        }

        // check that user has more than voting treshold of maxStakeCap and maxLockCap
        if (
            vePtpBalance * invVoteThreshold >
            users[_addr].amount * maxStakeCap + lockedPositions[_addr].ptpLocked * maxLockCap
        ) {
            return vePtpBalance;
        } else {
            return 0;
        }
    }

    function vote(address _user, int256 _voteDelta) external {
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
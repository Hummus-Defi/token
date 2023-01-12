// SPDX-License-Identifier: MIT

// pragma solidity 0.8.9;

// import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
// import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
// import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
// import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
// import './VeERC20Upgradeable.sol';
// import './Whitelist.sol';
// import './interfaces/IMasterPlatypus.sol';
// import './libraries/Math.sol';
// import './libraries/SafeOwnableUpgradeable.sol';
// import './interfaces/IVePtp.sol';
// import './interfaces/IPlatypusNFT.sol';

// interface IVe {
//     function vote(address _user, int256 _voteDelta) external;
// }

// /// @title VePtpV2
// /// @notice Platypus Venom: the staking contract for PTP, as well as the token used for governance.
// /// Note Venom does not seem to hurt the Platypus, it only makes it stronger.
// /// Allows depositing/withdraw of ptp and staking/unstaking ERC721.
// /// Here are the rules of the game:
// /// If you stake ptp, you generate vePtp at the current `generationRate` until you reach `maxCap`
// /// If you unstake any amount of ptp, you loose all of your vePtp.
// /// ERC721 staking does not affect generation nor cap for the moment, but it will in a future upgrade.
// /// Note that it's ownable and the owner wields tremendous power. The ownership
// /// will be transferred to a governance smart contract once Platypus is sufficiently
// /// distributed and the community can show to govern itself.
// /// - check vote
// /// https://snowtrace.io/address/0x9954d7d209e09171ee53500abc4f128f9d1c11bf
// contract VePtpV2 is
//     Initializable,
//     SafeOwnableUpgradeable,
//     ReentrancyGuardUpgradeable,
//     PausableUpgradeable,
//     VeERC20Upgradeable,
//     IVePtp,
//     IVe
// {
//     struct UserInfo {
//         uint256 amount; // ptp staked by user
//         uint256 lastRelease; // time of last vePtp claim or first deposit if user has not claimed yet
//         // the id of the currently staked nft
//         // important note: the id is offset by +1 to handle tokenID = 0
//         // stakedNftId = 0 (default value) means that no NFT is staked
//         uint256 stakedNftId;
//     }

//     /// @notice the ptp token
//     IERC20 public ptp;

//     /// @notice the masterPlatypus contract
//     IMasterPlatypus public masterPlatypus;

//     /// @notice the NFT contract
//     IPlatypusNFT public nft;

//     /// @notice max vePtp to staked ptp ratio
//     /// Note if user has 10 ptp staked, they can only have a max of 10 * maxCap vePtp in balance
//     uint256 public maxCap;

//     /// @notice the rate of vePtp generated per second, per ptp staked
//     uint256 public generationRate;

//     /// @notice invVvoteThreshold threshold.
//     /// @notice voteThreshold is the tercentage of cap from which votes starts to count for governance proposals.
//     /// @dev inverse of the threshold to apply.
//     /// Example: th = 5% => (1/5) * 100 => invVoteThreshold = 20
//     /// Example 2: th = 3.03% => (1/3.03) * 100 => invVoteThreshold = 33
//     /// Formula is invVoteThreshold = (1 / th) * 100
//     uint256 public invVoteThreshold;

//     /// @notice whitelist wallet checker
//     /// @dev contract addresses are by default unable to stake ptp, they must be previously whitelisted to stake ptp
//     Whitelist public whitelist;

//     /// @notice user info mapping
//     mapping(address => UserInfo) public users;

//     uint256 public maxNftLevel;
//     uint256 public xpEnableTime;

//     // reserve more space for extensibility
//     uint256[100] public xpRequiredForLevelUp;

//     address public voter;

//     /// @notice amount of vote used currently for each user
//     mapping(address => uint256) public usedVote;
//     /// @notice store the last block when a contract stake NFT
//     mapping(address => uint256) internal lastBlockToStakeNftByContract;

//     // Note used to prevent storage collision
//     uint256[2] private __gap;

//     /// @notice events describing staking, unstaking and claiming
//     event Staked(address indexed user, uint256 indexed amount);
//     event Unstaked(address indexed user, uint256 indexed amount);
//     event Claimed(address indexed user, uint256 indexed amount);

//     /// @notice events describing NFT staking and unstaking
//     event StakedNft(address indexed user, uint256 indexed nftId);
//     event UnstakedNft(address indexed user, uint256 indexed nftId);

//     function initialize(
//         IERC20 _ptp,
//         IMasterPlatypus _masterPlatypus,
//         IPlatypusNFT _nft
//     ) public initializer {
//         require(address(_masterPlatypus) != address(0), 'zero address');
//         require(address(_ptp) != address(0), 'zero address');
//         require(address(_nft) != address(0), 'zero address');

//         // Initialize vePTP
//         __ERC20_init('Platypus Venom', 'vePTP');
//         __Ownable_init();
//         __ReentrancyGuard_init_unchained();
//         __Pausable_init_unchained();

//         // set generationRate (vePtp per sec per ptp staked)
//         generationRate = 3888888888888;

//         // set maxCap
//         maxCap = 100;

//         // set inv vote threshold
//         // invVoteThreshold = 20 => th = 5
//         invVoteThreshold = 20;

//         // set master platypus
//         masterPlatypus = _masterPlatypus;

//         // set ptp
//         ptp = _ptp;

//         // set nft, can be zero address at first
//         nft = _nft;

//         initializeNft();
//     }

//     function _verifyVoteIsEnough(address _user) internal view {
//         require(balanceOf(_user) >= usedVote[_user], 'VePtp: not enough vote');
//     }

//     function _onlyVoter() internal view {
//         require(msg.sender == voter, 'VePtp: caller is not voter');
//     }

//     function initializeNft() public onlyOwner {
//         maxNftLevel = 1; // to enable leveling, call setMaxNftLevel
//         xpRequiredForLevelUp = [uint256(0), 3000 ether, 30000 ether, 300000 ether, 3000000 ether];
//     }

//     /**
//      * @dev pause pool, restricting certain operations
//      */
//     function pause() external onlyOwner {
//         _pause();
//     }

//     /**
//      * @dev unpause pool, enabling certain operations
//      */
//     function unpause() external onlyOwner {
//         _unpause();
//     }

//     /// @notice sets masterPlatpus address
//     /// @param _masterPlatypus the new masterPlatypus address
//     function setMasterPlatypus(IMasterPlatypus _masterPlatypus) external onlyOwner {
//         require(address(_masterPlatypus) != address(0), 'zero address');
//         masterPlatypus = _masterPlatypus;
//     }

//     /// @notice sets NFT contract address
//     /// @param _nft the new NFT contract address
//     function setNftAddress(IPlatypusNFT _nft) external onlyOwner {
//         require(address(_nft) != address(0), 'zero address');
//         nft = _nft;
//     }

//     /// @notice sets voter contract address
//     /// @param _voter the new NFT contract address
//     function setVoter(address _voter) external onlyOwner {
//         require(address(_voter) != address(0), 'zero address');
//         voter = _voter;
//     }

//     /// @notice sets whitelist address
//     /// @param _whitelist the new whitelist address
//     function setWhitelist(Whitelist _whitelist) external onlyOwner {
//         require(address(_whitelist) != address(0), 'zero address');
//         whitelist = _whitelist;
//     }

//     /// @notice sets maxCap
//     /// @param _maxCap the new max ratio
//     function setMaxCap(uint256 _maxCap) external onlyOwner {
//         require(_maxCap != 0, 'max cap cannot be zero');
//         maxCap = _maxCap;
//     }

//     /// @notice sets generation rate
//     /// @param _generationRate the new max ratio
//     function setGenerationRate(uint256 _generationRate) external onlyOwner {
//         require(_generationRate != 0, 'generation rate cannot be zero');
//         generationRate = _generationRate;
//     }

//     /// @notice sets invVoteThreshold
//     /// @param _invVoteThreshold the new var
//     /// Formula is invVoteThreshold = (1 / th) * 100
//     function setInvVoteThreshold(uint256 _invVoteThreshold) external onlyOwner {
//         require(_invVoteThreshold != 0, 'invVoteThreshold cannot be zero');
//         invVoteThreshold = _invVoteThreshold;
//     }

//     /// @notice sets setMaxNftLevel, the first time this function is called, leveling will be enabled
//     /// @param _maxNftLevel the new var
//     function setMaxNftLevel(uint8 _maxNftLevel) external onlyOwner {
//         maxNftLevel = _maxNftLevel;

//         if (xpEnableTime == 0) {
//             // enable users to accumulate timestamp the first time this function is invoked
//             xpEnableTime = block.timestamp;
//         }
//     }

//     /// @notice checks wether user _addr has ptp staked
//     /// @param _addr the user address to check
//     /// @return true if the user has ptp in stake, false otherwise
//     function isUser(address _addr) public view override returns (bool) {
//         return users[_addr].amount > 0;
//     }

//     /// @notice returns staked amount of ptp for user
//     /// @param _addr the user address to check
//     /// @return staked amount of ptp
//     function getStakedPtp(address _addr) external view override returns (uint256) {
//         return users[_addr].amount;
//     }

//     /// @dev explicity override multiple inheritance
//     function totalSupply() public view override(VeERC20Upgradeable, IVeERC20) returns (uint256) {
//         return super.totalSupply();
//     }

//     /// @dev explicity override multiple inheritance
//     function balanceOf(address account) public view override(VeERC20Upgradeable, IVeERC20) returns (uint256) {
//         return super.balanceOf(account);
//     }

//     /// @notice deposits PTP into contract
//     /// @param _amount the amount of ptp to deposit
//     function deposit(uint256 _amount) external override nonReentrant whenNotPaused {
//         require(_amount > 0, 'amount to deposit cannot be zero');

//         // assert call is not coming from a smart contract
//         // unless it is whitelisted
//         _assertNotContract(msg.sender);

//         if (isUser(msg.sender)) {
//             // if user exists, first, claim his vePTP
//             _claim(msg.sender);
//             // then, increment his holdings
//             users[msg.sender].amount += _amount;
//         } else {
//             // add new user to mapping
//             users[msg.sender].lastRelease = block.timestamp;
//             users[msg.sender].amount = _amount;
//         }

//         // Request Ptp from user
//         // SafeERC20 is not needed as PTP will revert if transfer fails
//         ptp.transferFrom(msg.sender, address(this), _amount);

//         // emit event
//         emit Staked(msg.sender, _amount);
//     }

//     /// @notice asserts addres in param is not a smart contract.
//     /// @notice if it is a smart contract, check that it is whitelisted
//     /// @param _addr the address to check
//     function _assertNotContract(address _addr) private view {
//         if (_addr != tx.origin) {
//             require(
//                 address(whitelist) != address(0) && whitelist.check(_addr),
//                 'Smart contract depositors not allowed'
//             );
//         }
//     }

//     /// @notice claims accumulated vePTP
//     function claim() external override nonReentrant whenNotPaused {
//         require(isUser(msg.sender), 'user has no stake');
//         _claim(msg.sender);
//     }

//     /// @dev private claim function
//     /// @param _addr the address of the user to claim from
//     function _claim(address _addr) private {
//         uint256 amount;
//         uint256 xp;
//         (amount, xp) = _claimable(_addr);

//         UserInfo storage user = users[_addr];

//         // update last release time
//         user.lastRelease = block.timestamp;

//         if (amount > 0) {
//             emit Claimed(_addr, amount);
//             _mint(_addr, amount);
//         }

//         if (xp > 0) {
//             uint256 nftId = user.stakedNftId;

//             // if nftId > 0, user has nft staked
//             if (nftId > 0) {
//                 --nftId; // remove offset

//                 // level is already validated in _claimable()
//                 nft.growXp(nftId, xp);
//             }
//         }
//     }

//     /// @notice Calculate the amount of vePTP that can be claimed by user
//     /// @param _addr the address to check
//     /// @return amount of vePTP that can be claimed by user
//     function claimable(address _addr) external view returns (uint256 amount) {
//         require(_addr != address(0), 'zero address');
//         (amount, ) = _claimable(_addr);
//     }

//     /// @notice Calculate the amount of vePTP that can be claimed by user
//     /// @param _addr the address to check
//     /// @return amount of vePTP that can be claimed by user
//     /// @return xp potential xp for NFT staked
//     function claimableWithXp(address _addr) external view returns (uint256 amount, uint256 xp) {
//         require(_addr != address(0), 'zero address');
//         return _claimable(_addr);
//     }

//     /// @notice Calculate the amount of vePTP that can be claimed by user
//     /// @dev private claimable function
//     /// @param _addr the address to check
//     /// @return amount of vePTP that can be claimed by user
//     /// @return xp potential xp for NFT staked
//     function _claimable(address _addr) private view returns (uint256 amount, uint256 xp) {
//         UserInfo storage user = users[_addr];

//         // get seconds elapsed since last claim
//         uint256 secondsElapsed = block.timestamp - user.lastRelease;

//         // calculate pending amount
//         // Math.mwmul used to multiply wad numbers
//         uint256 pending = Math.wmul(user.amount, secondsElapsed * generationRate);

//         // get user's vePTP balance
//         uint256 userVePtpBalance = balanceOf(_addr);

//         // user vePTP balance cannot go above user.amount * maxCap
//         uint256 maxVePtpCap = user.amount * maxCap;

//         // handle nft effects
//         uint256 nftId = user.stakedNftId;
//         // if nftId > 0, user has nft staked
//         if (nftId > 0) {
//             --nftId; // remove offset
//             uint32 speedo;
//             uint32 pudgy;
//             uint32 diligent;
//             uint32 gifted;
//             (speedo, pudgy, diligent, gifted, ) = nft.getPlatypusDetails(nftId);

//             if (speedo > 0) {
//                 // Speedo: x% faster vePTP generation
//                 pending = (pending * (100 + speedo)) / 100;
//             }
//             if (diligent > 0) {
//                 // Diligent: +D vePTP every hour (subject to cap)
//                 pending += ((uint256(diligent) * (10**decimals())) * secondsElapsed) / 1 hours;
//             }
//             if (pudgy > 0) {
//                 // Pudgy: x% higher vePTP cap
//                 maxVePtpCap = (maxVePtpCap * (100 + pudgy)) / 100;
//             }
//             if (gifted > 0) {
//                 // Gifted: +D vePTP regardless of PTP staked
//                 // The cap should also increase D
//                 maxVePtpCap += uint256(gifted) * (10**decimals());
//             }

//             uint256 level = nft.getPlatypusLevel(nftId);
//             if (level < maxNftLevel) {
//                 // Accumulate XP only after leveling is enabled
//                 if (user.lastRelease >= xpEnableTime) {
//                     xp = pending;
//                 } else {
//                     xp = (pending * (block.timestamp - xpEnableTime)) / (block.timestamp - user.lastRelease);
//                 }
//                 uint256 currentXp = nft.getPlatypusXp(nftId);

//                 if (xp + currentXp > xpRequiredForLevelUp[level]) {
//                     xp = xpRequiredForLevelUp[level] - currentXp;
//                 }
//             }
//         }

//         // first, check that user hasn't reached the max limit yet
//         if (userVePtpBalance < maxVePtpCap) {
//             // amount of vePTP to reach max cap
//             uint256 amountToCap = maxVePtpCap - userVePtpBalance;

//             // then, check if pending amount will make user balance overpass maximum amount
//             if (pending >= amountToCap) {
//                 amount = amountToCap;
//             } else {
//                 amount = pending;
//             }
//         } else {
//             amount = 0;
//         }
//         // Note: maxVePtpCap doesn't affect growing XP
//     }

//     /// @notice withdraws staked ptp
//     /// @param _amount the amount of ptp to unstake
//     /// Note Beware! you will loose all of your vePTP if you unstake any amount of ptp!
//     /// Besides, if you withdraw all PTP and you have staked NFT, it will be unstaked
//     function withdraw(uint256 _amount) external override nonReentrant whenNotPaused {
//         require(_amount > 0, 'amount to withdraw cannot be zero');
//         require(users[msg.sender].amount >= _amount, 'not enough balance');

//         uint256 nftId = users[msg.sender].stakedNftId;
//         if (nftId > 0) {
//             // claim to grow XP
//             _claim(msg.sender);
//         } else {
//             users[msg.sender].lastRelease = block.timestamp;
//         }

//         // get user vePTP balance that must be burned before updating his balance
//         uint256 valueToBurn = _vePtpBurnedOnWithdraw(msg.sender, _amount);

//         // update his balance before burning or sending back ptp
//         users[msg.sender].amount -= _amount;

//         _burn(msg.sender, valueToBurn);

//         // unstake NFT if all PTP is unstaked
//         if (users[msg.sender].amount == 0 && users[msg.sender].stakedNftId != 0) {
//             _unstakeNft(msg.sender);
//         }

//         // send back the staked ptp
//         // SafeERC20 is not needed as PTP will revert if transfer fails
//         ptp.transfer(msg.sender, _amount);

//         // emit event
//         emit Unstaked(msg.sender, _amount);
//     }

//     /// Calculate the amount of vePTP that will be burned when PTP is withdrawn
//     /// @param _amount the amount of ptp to unstake
//     /// @return the amount of vePTP that will be burned
//     function vePtpBurnedOnWithdraw(address _addr, uint256 _amount) external view returns (uint256) {
//         return _vePtpBurnedOnWithdraw(_addr, _amount);
//     }

//     /// Private function to calculate the amount of vePTP that will be burned when PTP is withdrawn
//     /// @param _amount the amount of ptp to unstake
//     /// @return the amount of vePTP that will be burned
//     function _vePtpBurnedOnWithdraw(address _addr, uint256 _amount) private view returns (uint256) {
//         require(_amount <= users[_addr].amount, 'not enough ptp');
//         uint256 vePtpBalance = balanceOf(_addr);
//         uint256 nftId = users[_addr].stakedNftId;

//         if (nftId == 0) {
//             // user doesn't have nft staked
//             return vePtpBalance;
//         } else {
//             --nftId; // remove offset
//             (, , , uint32 gifted, uint32 hibernate) = nft.getPlatypusDetails(nftId);

//             if (gifted > 0) {
//                 // Gifted: don't burn vePtp given by Gifted
//                 vePtpBalance -= uint256(gifted) * (10**decimals());
//             }

//             // retain some vePTP using nft
//             // if it is a smart contract, check lastBlockToStakeNftByContract is not the current block
//             // in case of flash loan attack
//             if (
//                 hibernate > 0 && (msg.sender == tx.origin || lastBlockToStakeNftByContract[msg.sender] != block.number)
//             ) {
//                 // Hibernate: Retain x% vePTP of cap upon unstaking
//                 return
//                     vePtpBalance -
//                     (vePtpBalance * hibernate * (users[_addr].amount - _amount)) /
//                     users[_addr].amount /
//                     100;
//             } else {
//                 return vePtpBalance;
//             }
//         }
//     }

//     /// @notice hook called after token operation mint/burn
//     /// @dev updates masterPlatypus
//     /// @param _account the account being affected
//     /// @param _newBalance the newVePtpBalance of the user
//     function _afterTokenOperation(address _account, uint256 _newBalance) internal override {
//         _verifyVoteIsEnough(_account);
//         masterPlatypus.updateFactor(_account, _newBalance);
//     }

//     /// @notice This function is called when users stake NFTs
//     function stakeNft(uint256 _tokenId) external override nonReentrant whenNotPaused {
//         require(isUser(msg.sender), 'user has no stake');

//         nft.transferFrom(msg.sender, address(this), _tokenId);

//         // first, claim his vePTP
//         _claim(msg.sender);

//         // user has previously staked some NFT, try to unstake it
//         if (users[msg.sender].stakedNftId != 0) {
//             _unstakeNft(msg.sender);
//         }

//         users[msg.sender].stakedNftId = _tokenId + 1; // add offset

//         if (msg.sender != tx.origin) {
//             lastBlockToStakeNftByContract[msg.sender] = block.number;
//         }

//         _afterNftStake(msg.sender, _tokenId);
//         emit StakedNft(msg.sender, _tokenId);
//     }

//     function _afterNftStake(address _addr, uint256 nftId) private {
//         uint32 gifted;
//         (, , , gifted, ) = nft.getPlatypusDetails(nftId);
//         // mint vePTP using nft
//         if (gifted > 0) {
//             // Gifted: +D vePTP regardless of PTP staked
//             _mint(_addr, uint256(gifted) * (10**decimals()));
//         }
//     }

//     /// @notice unstakes current user nft
//     function unstakeNft() external override nonReentrant whenNotPaused {
//         // first, claim his vePTP
//         // one should always has deposited if he has staked NFT
//         _claim(msg.sender);

//         _unstakeNft(msg.sender);
//     }

//     /// @notice private function used to unstake nft
//     /// @param _addr the address of the nft owner
//     function _unstakeNft(address _addr) private {
//         uint256 nftId = users[_addr].stakedNftId;
//         require(nftId > 0, 'No NFT is staked');
//         --nftId; // remove offset

//         nft.transferFrom(address(this), _addr, nftId);

//         users[_addr].stakedNftId = 0;

//         _afterNftUnstake(_addr, nftId);
//         emit UnstakedNft(_addr, nftId);
//     }

//     function _afterNftUnstake(address _addr, uint256 nftId) private {
//         uint32 gifted;
//         (, , , gifted, ) = nft.getPlatypusDetails(nftId);
//         // burn vePTP minted by nft
//         if (gifted > 0) {
//             // Gifted: +D vePTP regardless of PTP staked
//             _burn(_addr, uint256(gifted) * (10**decimals()));
//         }
//     }

//     /// @notice gets id of the staked nft
//     /// @param _addr the addres of the nft staker
//     /// @return id of the staked nft by _addr user
//     /// if the user haven't stake any nft, tx reverts
//     function getStakedNft(address _addr) external view returns (uint256) {
//         uint256 nftId = users[_addr].stakedNftId;
//         require(nftId > 0, 'not staking NFT');
//         return nftId - 1; // remove offset
//     }

//     /// @notice level up the staked NFT
//     /// @param platypusToBurn token IDs of platypuses to burn
//     function levelUp(uint256[] calldata platypusToBurn) external override nonReentrant whenNotPaused {
//         uint256 nftId = users[msg.sender].stakedNftId;
//         require(nftId > 0, 'not staking NFT');
//         --nftId; // remove offset

//         uint16 level = nft.getPlatypusLevel(nftId);
//         require(level < maxNftLevel, 'max level reached');

//         uint256 sumOfLevels;

//         for (uint256 i; i < platypusToBurn.length; ++i) {
//             uint256 level_ = nft.getPlatypusLevel(platypusToBurn[i]); // 1 - 5
//             uint256 exp = nft.getPlatypusXp(platypusToBurn[i]);

//             // only count levels which maxXp is reached;
//             sumOfLevels += level_ - 1;
//             if (exp >= xpRequiredForLevelUp[level_]) {
//                 ++sumOfLevels;
//             } else {
//                 require(level_ > 1, 'invalid platypusToBurn');
//             }
//         }
//         require(sumOfLevels >= level, 'vePTP: wut are you burning?');

//         // claim veptp before level up
//         _claim(msg.sender);

//         // Remove effect from Gifted
//         _afterNftUnstake(msg.sender, nftId);

//         // require XP
//         require(nft.getPlatypusXp(nftId) >= xpRequiredForLevelUp[level], 'vePTP: XP not enough');

//         // skill acquiring
//         // acquire the primary skill of a burned platypus
//         {
//             uint256 contributor = 0;
//             if (platypusToBurn.length > 1) {
//                 uint256 seed = _enoughRandom();
//                 contributor = (seed >> 8) % platypusToBurn.length;
//             }

//             uint256 newAbility;
//             uint256 newPower;
//             (newAbility, newPower) = nft.getPrimaryAbility(platypusToBurn[contributor]);
//             nft.levelUp(nftId, newAbility, newPower);
//             require(nft.getPlatypusXp(nftId) == 0, 'vePTP: XP should reset');
//         }

//         masterPlatypus.updateFactor(msg.sender, balanceOf(msg.sender));

//         // Re apply effect for Gifted
//         _afterNftStake(msg.sender, nftId);

//         // burn platypuses
//         for (uint16 i = 0; i < platypusToBurn.length; ++i) {
//             require(nft.ownerOf(platypusToBurn[i]) == msg.sender, 'vePTP: not owner');
//             nft.burn(platypusToBurn[i]);
//         }
//     }

//     /// @dev your sure?
//     function _enoughRandom() private view returns (uint256) {
//         return
//             uint256(
//                 keccak256(
//                     abi.encodePacked(
//                         // solhint-disable-next-line
//                         block.timestamp,
//                         msg.sender,
//                         blockhash(block.number - 1)
//                     )
//                 )
//             );
//     }

//     /// @notice level down the staked NFT
//     function levelDown() external override nonReentrant whenNotPaused {
//         uint256 nftId = users[msg.sender].stakedNftId;
//         require(nftId > 0, 'not staking NFT');
//         --nftId; // remove offset

//         require(nft.getPlatypusLevel(nftId) > 1, 'wut?');

//         _claim(msg.sender);

//         // Remove effect from Gifted
//         _afterNftUnstake(msg.sender, nftId);

//         nft.levelDown(nftId);

//         // grow to max XP after leveling down
//         uint256 maxXp = xpRequiredForLevelUp[nft.getPlatypusLevel(nftId)];
//         nft.growXp(nftId, maxXp);

//         // Apply effect for Gifted
//         _afterNftStake(msg.sender, nftId);

//         // veptp should be capped
//         uint32 pudgy;
//         uint32 gifted;
//         (, pudgy, , gifted, ) = nft.getPlatypusDetails(nftId);
//         uint256 maxVePtpCap = users[msg.sender].amount * maxCap;
//         maxVePtpCap = (maxVePtpCap * (100 + pudgy)) / 100 + uint256(gifted) * (10**decimals());

//         if (balanceOf(msg.sender) > maxVePtpCap) {
//             _burn(msg.sender, balanceOf(msg.sender) - maxVePtpCap);
//         }

//         masterPlatypus.updateFactor(msg.sender, balanceOf(msg.sender));
//     }

//     /// @notice get votes for vePTP
//     /// @dev votes should only count if account has > threshold% of current cap reached
//     /// @dev invVoteThreshold = (1/threshold%)*100
//     /// @param _addr the addres of the nft staker
//     /// @return the valid votes
//     function getVotes(address _addr) external view virtual override returns (uint256) {
//         uint256 vePtpBalance = balanceOf(_addr);

//         uint256 nftId = users[_addr].stakedNftId;
//         // if nftId > 0, user has nft staked
//         if (nftId > 0) {
//             --nftId; //remove offset
//             uint32 gifted;
//             (, , , gifted, ) = nft.getPlatypusDetails(nftId);
//             // burn vePTP minted by nft
//             if (gifted > 0) {
//                 vePtpBalance -= uint256(gifted) * (10**decimals());
//             }
//         }

//         // check that user has more than voting treshold of maxCap and has ptp in stake
//         if (vePtpBalance * invVoteThreshold > users[_addr].amount * maxCap) {
//             return vePtpBalance;
//         } else {
//             return 0;
//         }
//     }

//     function vote(address _user, int256 _voteDelta) external {
//         _onlyVoter();

//         if (_voteDelta >= 0) {
//             usedVote[_user] += uint256(_voteDelta);
//             _verifyVoteIsEnough(_user);
//         } else {
//             // reverts if usedVote[_user] < -_voteDelta
//             usedVote[_user] -= uint256(-_voteDelta);
//         }
//     }
// }

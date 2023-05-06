// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StakingPool is ERC721Holder, Ownable, ReentrancyGuard {
  uint256 public minStakingTime = 259200; // min stakingTime is 3days for Both Type of NFTs
  uint256 public plantNFTPerSecReward = 7;
  uint256 public treeNFTPerSecReward = 10; //reward on 1 sec staking

  //NFTsType
  uint8 public plantNFTType = 1;
  uint8 public treeNFTType = 2;

  IERC20 public immutable rewardToken;
  IERC721 public immutable creditNFT;

  //structs
  struct userNFTStakingData {
    uint256 stakeTime;
    uint256 unstakeTime;
    uint256 rewardClaimTimeStart;
    uint256 nftId;
    uint8 nftType;
    bool agreeToPayFee;
  }

  struct UserStakedNFTsRecord {
    uint256 totalStakedNFTs;
    uint256[] stakedNftIds;
  }
  //mappings
  mapping(address => userNFTStakingData[]) private _userNFTStakingData;
  mapping(address => UserStakedNFTsRecord) public _userStakedNFTsRecord;

  //Events
  event Stake(address indexed _staker, uint256 _nftStaked, uint8 _nftType);
  event unStaketake(address indexed _unStaker, uint256 _nftUnstaked);
  event ClaimRewards(address indexed _claimer, uint256 _claimedRewards);

  constructor(address _rewardToken, address _creditNFT) {
    rewardToken = IERC20(_rewardToken);
    creditNFT = IERC721(_creditNFT);
  }

  //Stake
  function stakeNFT(
    uint256 _nftId,
    uint8 _nftType,
    bool _agreeToPayFee
  ) external nonReentrant {
    require(
      _nftType == plantNFTType || _nftType == treeNFTType,
      "Invalid NFT Type"
    );
    require(_nftId != 0, "Invalid NFT Id");
    if (_nftType == 1) {
      require(creditNFT.isPlantNFT(_nftId), "Invalid Plant NFT");
      _stakeNFT(_nftId, _nftType, _agreeToPayFee);
    }

    if (_nftType == 2) {
      require(creditNFT.isTreeNFT(_nftId), "Invalid Tree NFT");
      _stakeNFT(_nftId, _nftType, _agreeToPayFee);
    }
    _transferCreditNFT(msg.sender, address(this), _nftId);
    emit Stake(msg.sender, _nftId, _nftType);
  }

  //Unstake
  function unstakeNFT(uint256 _nftId, uint256 _index) external nonReentrant {
    _unStakeNFT(_index);
    _transferCreditNFT(address(this), msg.sender, _nftId);
    //will send rewards if > 0
    if (_calculateRewards(msg.sender, _index) > 0) claimRewards(_index);
    emit unStaketake(msg.sender, _nftId);
  }

  //Claim Rewards
  function claimRewards(uint256 _index) public nonReentrant {
    userNFTStakingData memory stakedNFT = _userNFTStakingData[msg.sender][
      _index
    ];
    uint256 rewardTokens = _calculateRewards(msg.sender, _index);
    require(rewardTokens > 0, "Can't Claim Zero Rewards");
    stakedNFT.rewardClaimTimeStart = block.timestamp;
    rewardToken.transfer(msg.sender, rewardTokens);
    emit ClaimRewards(msg.sender, rewardTokens);
  }

  // Private Functions
  function _stakeNFT(
    uint256 _nftId,
    uint8 _nftType,
    bool _agreeToPayFee
  ) private {
    userNFTStakingData memory stakedNFT;
    UserStakedNFTsRecord storage userNfts = _userStakedNFTsRecord[msg.sender];

    //updating _userNFTStakingData mapping
    stakedNFT = userNFTStakingData({
      stakeTime: block.timestamp,
      unstakeTime: 0,
      rewardClaimTimeStart: block.timestamp,
      nftId: _nftId,
      nftType: _nftType,
      agreeToPayFee: _agreeToPayFee
    });
    _userNFTStakingData[msg.sender].push(stakedNFT);

    //updating _UserStakedNFTsRecord mapping
    userNfts.stakedNftIds.push(_nftId);
    userNfts.totalStakedNFTs++;
    _userStakedNFTsRecord[msg.sender] = userNfts;
  }

  function _unStakeNFT(uint256 _index) private {
    userNFTStakingData memory stakedNFT = _userNFTStakingData[msg.sender][
      _index
    ];
    UserStakedNFTsRecord storage userNFTsRecord = _userStakedNFTsRecord[
      msg.sender
    ];
    require(stakedNFT.stakeTime != 0, "Have not Staked ");
    require(
      block.timestamp > stakedNFT.stakeTime + minStakingTime,
      "Can't unstake now"
    );

    //_userNFTStakingData will be updated
    _userNFTStakingData[msg.sender][_index] = _userNFTStakingData[msg.sender][
      _userNFTStakingData[msg.sender].length - 1
    ];
    _userNFTStakingData[msg.sender].pop();

    // _userStakedNFTsRecord will be updated
    userNFTsRecord.totalStakedNFTs--;
    userNFTsRecord.stakedNftIds[_index] = userNFTsRecord.stakedNftIds[
      userNFTsRecord.stakedNftIds.length - 1
    ];
    userNFTsRecord.stakedNftIds.pop();
  }

  function _calculateRewards(
    address _address,
    uint256 _index
  ) public view returns (uint256) {
    userNFTStakingData memory stakedNFT = _userNFTStakingData[_address][_index];
    uint8 _nftType = stakedNFT.nftType;
    uint256 rewardTokens;
    if (_nftType == 1) {
      if (stakedNFT.agreeToPayFee) {
        rewardTokens =
          (block.timestamp - stakedNFT.rewardClaimTimeStart) *
          plantNFTPerSecReward;
      } else {
        rewardTokens = 0;
      }
    }

    if (_nftType == 2) {
      if (stakedNFT.agreeToPayFee) {
        rewardTokens =
          (block.timestamp - stakedNFT.rewardClaimTimeStart) *
          treeNFTPerSecReward;
      } else {
        rewardTokens = 0;
      }
    }
    return rewardTokens;
  }

  function _transferCreditNFT(
    address from,
    address to,
    uint256 _nftId
  ) private {
    creditNFT.safeTransferFrom(from, to, _nftId);
  }

  function _isNotZero(uint256 _value) private pure {
    require(_value != 0, "Invalid Value");
  }

  // updatable functions only Owner
  function updateMinStakingTime(uint256 _minTime) external onlyOwner {
    _isNotZero(_minTime);
    minStakingTime = _minTime;
  }

  function updateTreeRewardPerSec(uint256 _rewardPerSec) external onlyOwner {
    _isNotZero(_rewardPerSec);
    treeNFTPerSecReward = _rewardPerSec;
  }

  function updateplantRewardPerSec(uint256 _rewardPerSec) external onlyOwner {
    _isNotZero(_rewardPerSec);
    plantNFTPerSecReward = _rewardPerSec;
  }
}

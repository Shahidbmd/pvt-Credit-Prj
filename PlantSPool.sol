// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PlantStakingPool is ERC721Holder, Ownable, ReentrancyGuard {
  uint256 public stakingFeePLantNFT = 0.007 ether; // plant NFT StakeFee
  uint256 public minStakingTime = 259200; // min stakingTime is 3days Plant  NFTs
  uint256 public plantNFTPerSecReward = 0.000000000007 ether; //reward on 1 sec staking
  uint256 public plantMaintainanceFee = 0.0005 ether; // plant maintainance Fee
  uint256 public maintainanceFeeDeadline = 30 days; //after 30 days will pay maintananceFee
  uint256 public claimFee = 5; // 5 % fee on claim (in form of Credit Token
  uint256 private claimFeeBurn = 50; //  50% of claimFee will sent to dead address
  uint256 private claimFeeDev = 25; // 50% of claimFee will sent to developmentProject wallet
  uint256 private claimFeeSuportOp = 25; // 50% of claimFee will sent to Support Operation Fee wallet
  uint256 private totalClaimedFee;

  //wallet addreses
  address public maintanceFeeWallet =
    0x9f27d8958B96B7Ecf3117184A252DC8d2bb7463D;
  address public supportOpWallet = 0xeb4C27e545e24aB5ac8b4bb2ba1020263ce02237;
  address public projectDevWallet = 0x3A9916516c451572fdA4EEa7037dae94877eE4BC;
  address public deadAddress = address(0xdead);
  //interfaces instances
  IERC20 public immutable creditToken;
  IERC721 public immutable plantNFT;

  //structs
  struct userNFTStakingData {
    uint256 stakeTime;
    uint256 unstakeTime;
    uint256 rewardClaimTimeStart;
    uint256 nftId;
    bool agreeToPayFee;
  }

  //mappings
  mapping(address => userNFTStakingData[]) private _userNFTStakingData;

  //Events
  event Stake(address indexed _staker, uint256 _nftStaked, bool _agreeToPayFee);
  event unStaketake(address indexed _unStaker, uint256 _nftUnstaked);
  event ClaimRewards(address indexed _claimer, uint256 _claimedRewards);

  constructor(address _creditToken, address _plantNFT) {
    creditToken = IERC20(_creditToken);
    plantNFT = IERC721(_plantNFT);
  }

  //Stake
  function stakeNFT(
    uint256 _nftId,
    bool _agreeToPayFee
  ) external payable nonReentrant {
    require(msg.value == stakingFeePLantNFT, "Invalid Staking Fee");
    require(_nftId != 0, "Invalid NFT Id");
    _stakeNFT(_nftId, _agreeToPayFee);
    _transferPlantNFT(msg.sender, address(this), _nftId);
    emit Stake(msg.sender, _nftId, _agreeToPayFee);
  }

  //Unstake
  function unstakeNFT(uint256 _nftId, uint256 _index) external nonReentrant {
    _unStakeNFT(_index);
    _transferPlantNFT(address(this), msg.sender, _nftId);
    //will send rewards if > 0
    if (_calculateRewards(msg.sender, _index) > 0) claimRewards(_index);
    emit unStaketake(msg.sender, _nftId);
  }

  //Claim Rewards
  function claimRewards(uint256 _index) public payable nonReentrant {
    userNFTStakingData memory stakedNFT = _userNFTStakingData[msg.sender][
      _index
    ];
    uint256 rewardsTokens = _calculateRewards(msg.sender, _index);
    require(rewardsTokens > 0, "Can't Claim Zero Rewards");
    if (block.timestamp >= maintainanceFeeDeadline + stakedNFT.stakeTime) {
      require(msg.value == plantMaintainanceFee, "Invalid Fee");
      (bool success, ) = payable(maintanceFeeWallet).call{ value: msg.value }(
        ""
      );
      require(success, "Can't Sent Maintaince Fee");
    }
    _transferClaimTokens(rewardsTokens);
    stakedNFT.rewardClaimTimeStart = block.timestamp;
    emit ClaimRewards(msg.sender, rewardsTokens);
  }

  // Private Functions
  function _stakeNFT(uint256 _nftId, bool _agreeToPayFee) private {
    userNFTStakingData memory stakedNFT;

    //updating _userNFTStakingData mapping
    stakedNFT = userNFTStakingData({
      stakeTime: block.timestamp,
      unstakeTime: 0,
      rewardClaimTimeStart: block.timestamp,
      nftId: _nftId,
      agreeToPayFee: _agreeToPayFee
    });
    _userNFTStakingData[msg.sender].push(stakedNFT);
  }

  function _unStakeNFT(uint256 _index) private {
    userNFTStakingData memory stakedNFT = _userNFTStakingData[msg.sender][
      _index
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
  }

  function _calculateRewards(
    address _address,
    uint256 _index
  ) public view returns (uint256) {
    userNFTStakingData memory stakedNFT = _userNFTStakingData[_address][_index];
    uint256 creditTokens;
    creditTokens =
      (block.timestamp - stakedNFT.rewardClaimTimeStart) *
      plantNFTPerSecReward;
    return creditTokens;
  }

  function _transferClaimTokens(uint256 _rewardsWithoutFee) private {
    uint256 _claimFee = (_rewardsWithoutFee * claimFee) / 100; // 5% Of the user total Rewards
    uint256 userRewards = _rewardsWithoutFee - _claimFee;
    totalClaimedFee += _claimFee;
    creditToken.transfer(msg.sender, userRewards); // will sent to user 95% tokens

    if (
      totalClaimedFee > 1000 ether &&
      creditToken.balanceOf(address(this)) > 1000 ether
    ) {
      creditToken.transfer(deadAddress, (totalClaimedFee * claimFeeBurn) / 100); // 50% of totalClaimedFeewill be burned
      creditToken.transfer(
        projectDevWallet,
        (totalClaimedFee * claimFeeDev) / 100
      ); // 25%  totalClaimedFee will sent to projectDevWallet
      creditToken.transfer(
        supportOpWallet,
        (totalClaimedFee * claimFeeSuportOp) / 100
      ); //// 25%  supportOpWallet will sent to projectDevWallet
      totalClaimedFee = 0;
    }
  }

  function _transferPlantNFT(address from, address to, uint256 _nftId) private {
    plantNFT.safeTransferFrom(from, to, _nftId);
  }

  function _isNotZero(uint256 _value) private pure {
    require(_value != 0, "Invalid Value");
  }

  // updatable functions only Owner
  function updateMinStakingTime(uint256 _minTime) external onlyOwner {
    _isNotZero(_minTime);
    minStakingTime = _minTime;
  }

  function updateplantRewardPerSec(uint256 _rewardPerSec) external onlyOwner {
    _isNotZero(_rewardPerSec);
    plantNFTPerSecReward = _rewardPerSec;
  }

  function updatePlantMFee(uint256 _newFee) external onlyOwner {
    _isNotZero(_newFee);
    plantMaintainanceFee = _newFee;
  }

  function updateMFeeDeadline(uint256 _newDeadline) external onlyOwner {
    maintainanceFeeDeadline = _newDeadline;
  }

  function updateMFeeWallet(address _newWallet) external onlyOwner {
    maintanceFeeWallet = _newWallet;
  }

  function updateClaimFee(uint256 _newFee) external onlyOwner {
    claimFee = _newFee;
  }

  function updateSupportOpWallet(address _newAddress) external onlyOwner {
    maintanceFeeWallet = _newAddress;
  }

  function updateMaintainWallet(address _newAddress) external onlyOwner {
    maintanceFeeWallet = _newAddress;
  }

  function updateDevWallet(address _newAddress) external onlyOwner {
    maintanceFeeWallet = _newAddress;
  }

  function updateClaimBurnPercent(uint256 _newBurnPercent) external onlyOwner {
    claimFeeBurn = _newBurnPercent;
  }

  function updateClaimDevPercent(uint256 _newDevPercent) external onlyOwner {
    claimFeeDev = _newDevPercent;
  }

  function updateClaimSupportOpPercent(
    uint256 _newSupportOpPercent
  ) external onlyOwner {
    claimFeeSuportOp = _newSupportOpPercent;
  }
}

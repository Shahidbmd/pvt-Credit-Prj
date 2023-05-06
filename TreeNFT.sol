// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TreeNFT is ERC721, Ownable, ReentrancyGuard {
  using Counters for Counters.Counter;
  Counters.Counter private tokenId;
  IERC20 public creditToken;
  string private baseURI;
  uint256 public plantNFTMintFee = 0.00000000000001 ether;
  address private mintFeeReceiver = 0x9f27d8958B96B7Ecf3117184A252DC8d2bb7463D;

  constructor(address _creditToken) ERC721("Tree NFT", "TNFT") {
    _isValidAddress(_creditToken);
    creditToken = IERC20(_creditToken);
    tokenId.increment();
  }

  //mint Tree NFT
  function mintTreeNFT(address to) external nonReentrant returns (uint256) {
    _isValidAddress(to);
    creditToken.transferFrom(msg.sender, mintFeeReceiver, plantNFTMintFee);
    _mint(to, tokenId.current());
    return tokenId.current();
  }

  // burn Tree NFT
  function burnTreeNFT(uint256 _nftId) external nonReentrant returns (bool) {
    _burn(_nftId);
    return true;
  }

  // Update Minting Fee Only Owner
  function updateTreeNFTFee(uint256 _plantMintFee) external onlyOwner {
    _isValidFee(_plantMintFee);
    plantNFTMintFee = _plantMintFee;
  }

  //Update mintFeeReceiver onlyOwner
  function updateMintFeeReceiver(address _address) external onlyOwner {
    _isValidAddress(_address);
    mintFeeReceiver = _address;
  }

  //set URI only Owner
  function setBaseURIL(string memory _baseUri) external onlyOwner {
    require(bytes(_baseUri).length != 0, "Invalid URI");
    baseURI = _baseUri;
  }

  function _baseURI() internal view override returns (string memory) {
    return baseURI;
  }

  //Private Functions
  function _isValidAddress(address _address) private pure {
    require(_address != address(0), "Invalid Token  or Account Address");
  }

  function _isValidFee(uint256 _MintFee) private pure {
    require(_MintFee != 0, "Invalid Minting Fee");
  }
}

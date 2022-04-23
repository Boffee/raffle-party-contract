// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract DummyERC721 is ERC721 {
  uint256 public totalSupply;
  constructor() ERC721("Dummy", "DUMMY") {}

  function mint(address _to, uint256 amount) public {
    for (uint256 i = totalSupply; i < totalSupply + amount; i++) {
      _mint(_to, i);
    }
    totalSupply += amount;
  }
}

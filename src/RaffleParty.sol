// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title  A contract to raffle off NFT for ERC20 tokens
/// @author Critterz
contract RaffleParty {

  struct Prize {
    address tokenAddress;
    uint96 tokenId;
    address owner;
    uint88 weight;
    bool claimed;
  }

  struct Ticket {
    address owner;
    uint96 endId;
  }

  struct PoolPrizeTokenConfig {
    address tokenAddress;
    uint88 weight;
  }
  
  struct Raffle {
    address creator;
    uint256 ticketPrice;
    address paymentToken;
    uint96 minTickets;
    uint96 seed;
    uint48 startTimestamp;
    uint48 endTimestamp;
    uint96 totalWeight;
  }

  /*
   GLOBAL STATE
   */

  uint88 public constant BASE_WEIGHT = 10000;

  uint256 public raffleCount;

  mapping(uint256 => Raffle) public raffles;
  mapping(uint256 => Prize[]) public rafflePrizes;
  mapping(uint256 => PoolPrizeTokenConfig[]) public rafflePoolPrizeTokenConfigs;
  mapping(uint256 => Ticket[]) public raffleTickets;

  /*
  WRITE FUNCTIONS
  */

  /**
   * @notice initializes the raffle
   * @param prizeToken the address of the ERC721 token to raffle off
   * @param tokenId the list of token ids to raffle off
   * @param paymentToken address of the ERC20 token used to buy tickets. Null address uses ETH
   * @param startTimestamp the timestamp at which the raffle starts
   * @param endTimestamp the timestamp at which the raffle ends
   * @param ticketPrice the price of each ticket
   * @param minTickets the minimum number of tickets required for raffle to succeed
   * @return raffleId the id of the raffle
   */
  function createRaffle(
    address prizeToken,
    uint96 tokenId,
    address paymentToken,
    uint48 startTimestamp,
    uint48 endTimestamp,
    uint256 ticketPrice,
    uint96 minTickets
  ) public returns (uint256 raffleId) {
    require(prizeToken != address(0));
    require(endTimestamp > block.timestamp);
    require(ticketPrice > 0);

    // must have transfer approval from contract owner or token owner
    IERC721(prizeToken).transferFrom(msg.sender, address(this), tokenId);

    raffleId = raffleCount++;

    raffles[raffleId] = Raffle({
      creator: msg.sender,
      paymentToken: paymentToken,
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
      minTickets: minTickets,
      ticketPrice: ticketPrice,
      seed: 0,
      totalWeight: 10000
    });

    rafflePrizes[raffleId].push(Prize({
      tokenAddress: prizeToken,
      tokenId: tokenId,
      owner: msg.sender,
      weight: BASE_WEIGHT,
      claimed: false
    }));
  }
  
  function addPoolPrize(
    uint256 raffleId,
    address prizeToken,
    uint96 tokenId
  ) public {
    PoolPrizeTokenConfig memory config = getPoolPrizeTokenConfig(raffleId, prizeToken);
    IERC721(prizeToken).transferFrom(msg.sender, address(this), tokenId);
    rafflePrizes[raffleId].push(Prize({
      tokenAddress: prizeToken,
      tokenId: tokenId,
      owner: msg.sender,
      weight: config.weight,
      claimed: false
    }));
  }

  function cancelRaffle(
    uint256 raffleId
  ) public {
    require(msg.sender == raffles[raffleId].creator, "Only creator can cancel raffle");
    require(block.timestamp < raffles[raffleId].startTimestamp, "raffle has already started");
    // return all prizes to their owners
    Prize[] memory prizes = rafflePrizes[raffleId];
    for (uint256 i = 0; i < prizes.length; i++) {
      IERC721(prizes[i].tokenAddress).transferFrom(address(this), prizes[i].owner, prizes[i].tokenId);
    }
    delete raffles[raffleId];
  }
  
  /**
   * @notice buy ticket with erc20
   * @param raffleId the id of the raffle to buy ticket for
   * @param ticketCount the number of tickets to buy
   */
  function buyTicket(uint256 raffleId, uint96 ticketCount) public {
    // transfer payment token frm account
    uint256 cost = raffles[raffleId].ticketPrice * ticketCount;
    IERC20(raffles[raffleId].paymentToken).transfer(msg.sender, cost);
    // give tickets to account
    _sendTicket(msg.sender, raffleId, ticketCount);
  }

  /**
   * @notice buy ticket with ETH
   * @param raffleId the id of the raffle to buy ticket for
   * @param ticketCount the number of tickets to buy
   */
  function buyTicketEth(uint256 raffleId, uint96 ticketCount) public payable {
    // transfer payment token frm account
    uint256 cost = raffles[raffleId].ticketPrice * ticketCount;
    require(msg.value == cost, "Price mismatch");
    // give tickets to account
    _sendTicket(msg.sender, raffleId, ticketCount);
  }

  /**
   * @notice claim prize
   * @param to the winner address to send the prize to
   * @param prizeIndex the index of the prize to claim
   * @param ticketPurchaseIndex the index of the ticket purchase to claim prize for
   */
  function claimPrize(address to, uint256 raffleId, uint256 prizeIndex, uint256 ticketPurchaseIndex) public {
    require(raffles[raffleId].seed != 0, "Winner not set");
    require(to == raffleTickets[raffleId][ticketPurchaseIndex].owner, "Not ticket owner");
    uint256 ticketId = getWinnerTicketId(raffleId, prizeIndex);
    uint96 startId = raffleTickets[raffleId][ticketPurchaseIndex - 1].endId;
    uint96 endId = raffleTickets[raffleId][ticketPurchaseIndex].endId;
    require(ticketId >= startId && ticketId < endId, "Ticket id out of winner range");
    rafflePrizes[raffleId][prizeIndex].claimed = true;
    IERC721(rafflePrizes[raffleId][prizeIndex].tokenAddress).transferFrom(address(this), to, rafflePrizes[raffleId][prizeIndex].tokenId);
  }

  /**
   * @dev sends ticket to account
   * @param to the account to send ticket to
   * @param raffleId the id of the raffle to send ticket for
   * @param ticketCount the number of tickets to send
   */
  function _sendTicket(address to, uint256 raffleId, uint96 ticketCount) internal {
    uint96 ticketEndId = raffleTickets[raffleId][raffleTickets[raffleId].length - 1].endId + ticketCount;
    Ticket memory ticket = Ticket({owner: to, endId: ticketEndId});
    raffleTickets[raffleId].push(ticket);
  }

  /*
  READ FUNCTIONS
  */

  /**
   * @notice get config for pool prize
   * @param raffleId the id of the raffle
   * @param prizeToken the address of the prize token
   * @return config the config for the pool prize
   */
  function getPoolPrizeTokenConfig(uint256 raffleId, address prizeToken) public view returns (PoolPrizeTokenConfig memory config) {
    // NOTE consider changing config array to weight map for cheaper reads
    PoolPrizeTokenConfig[] memory configs = rafflePoolPrizeTokenConfigs[raffleId];
    for (uint256 i = 0; i < configs.length; i++) {
      if (configs[i].tokenAddress == prizeToken) {
        return config;
      }
    }
    revert("Pool prize address not found");
  }

  /**
   * @dev binary search for winner address
   * @param raffleId the id of the raffle to get winner for
   * @param prizeIndex the index of the prize to get winner for
   * @return winner the winner address
   */
  function getWinner(uint256 raffleId, uint256 prizeIndex) public view returns (address winner) {
    uint256 ticketId = getWinnerTicketId(raffleId, prizeIndex);
    uint256 ticketPurchaseIndex = getTicketPurchaseIndex(raffleId, ticketId);
    return raffleTickets[raffleId][ticketPurchaseIndex].owner;
  }

  /**
   * @dev binary search for ticket purchase index of ticketId
   * @param raffleId the id of the raffle to get winner for
   * @param ticketId the id of the ticket to get index for
   * @return ticketPurchaseIndex the purchase index of the ticket
   */
  function getTicketPurchaseIndex(uint256 raffleId, uint256 ticketId) public view returns (uint256 ticketPurchaseIndex) {
    // binary search for winner
    uint256 left = 0;
    uint256 right = raffleTickets[raffleId].length - 1;
    while (left < right) {
      uint256 mid = (left + right) / 2;
      if (raffleTickets[raffleId][mid].endId < ticketId) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }
    ticketPurchaseIndex = left;
  }

  /**
   * @dev salt the seed with prize index and get the winner ticket id
   * @param raffleId the id of the raffle to get winner for
   * @param prizeIndex the index of the prize to get winner for
   * @return ticketId the id of the ticket that won
   */
  function getWinnerTicketId(uint256 raffleId, uint256 prizeIndex) internal view returns (uint256 ticketId) {
    // add salt to seed
    ticketId = uint256(keccak256((abi.encode(raffleId, prizeIndex)))) % rafflePrizes[raffleId].length;
  }

  /*
  MODIFIERS
  */
}

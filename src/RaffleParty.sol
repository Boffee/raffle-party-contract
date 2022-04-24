// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title  A contract to raffle off NFT for ERC20 tokens
/// @author Critterz
contract RaffleParty is Ownable {
    struct Prize {
        address tokenAddress;
        uint96 tokenId;
        address owner;
        uint64 weight;
        bool claimed;
    }

    struct Ticket {
        address owner;
        uint96 endId;
    }

    struct RoyaltyPriceIndex {
        uint32 blockNumber;
        uint224 value;
    }

    struct PoolPrizeTokenConfig {
        address tokenAddress;
        uint64 weight;
    }

    struct Raffle {
        address creator;
        uint256 ticketPrice;
        bytes32 requestId;
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

    // weight in basis points
    uint64 public constant BASE_WEIGHT = 10000;

    // royalty in basis points
    uint256 public baseRoyalty = 250;
    uint256 public overflowRoyalty = 5000;

    uint256 public raffleCount;

    mapping(uint256 => Raffle) public raffles;
    mapping(uint256 => Prize[]) public rafflePrizes;
    mapping(uint256 => PoolPrizeTokenConfig[])
        public rafflePoolPrizeTokenConfigs;
    mapping(uint256 => Ticket[]) public raffleTickets;
    mapping(uint256 => mapping(address => uint96)) public raffleAccountWeights;
    mapping(bytes32 => uint256) public requestIdToRaffleId;

    mapping(address => RoyaltyPriceIndex[]) public royaltyPriceIndices;
    mapping(address => mapping(uint256 => uint256)) public blockNumberToIndex;

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
     * @param poolPrizeTokens the list of ERC721 tokens allowed to join the raffle pool
     * @param poolPrizeTokenWeights the list of weights of the ERC721 tokens allowed to join the raffle pool
     * @return raffleId the id of the raffle
     */
    function createRaffle(
        address prizeToken,
        uint96 tokenId,
        address paymentToken,
        uint48 startTimestamp,
        uint48 endTimestamp,
        uint256 ticketPrice,
        uint96 minTickets,
        address[] calldata poolPrizeTokens,
        uint64[] calldata poolPrizeTokenWeights
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
            requestId: bytes32(0),
            seed: 0,
            totalWeight: 10000
        });

        rafflePrizes[raffleId].push(
            Prize({
                tokenAddress: prizeToken,
                tokenId: tokenId,
                owner: msg.sender,
                weight: BASE_WEIGHT,
                claimed: false
            })
        );

        raffleAccountWeights[raffleId][msg.sender] = BASE_WEIGHT;

        for (uint256 i = 0; i < poolPrizeTokens.length; i++) {
            require(poolPrizeTokens[i] != address(0));
            require(poolPrizeTokenWeights[i] > 0);

            rafflePoolPrizeTokenConfigs[raffleId].push(
                PoolPrizeTokenConfig({
                    tokenAddress: poolPrizeTokens[i],
                    weight: poolPrizeTokenWeights[i]
                })
            );
        }
    }

    function addPoolPrize(
        uint256 raffleId,
        address prizeToken,
        uint96 tokenId
    ) public {
        PoolPrizeTokenConfig memory config = getPoolPrizeTokenConfig(
            raffleId,
            prizeToken
        );
        IERC721(prizeToken).transferFrom(msg.sender, address(this), tokenId);
        rafflePrizes[raffleId].push(
            Prize({
                tokenAddress: prizeToken,
                tokenId: tokenId,
                owner: msg.sender,
                weight: config.weight,
                claimed: false
            })
        );

        raffleAccountWeights[raffleId][msg.sender] += config.weight;
    }

    function cancelRaffle(uint256 raffleId) public {
        require(
            msg.sender == raffles[raffleId].creator,
            "Only creator can cancel raffle"
        );
        require(
            block.timestamp < raffles[raffleId].startTimestamp,
            "raffle has already started"
        );
        // return all prizes to their owners
        Prize[] memory prizes = rafflePrizes[raffleId];
        for (uint256 i = 0; i < prizes.length; i++) {
            IERC721(prizes[i].tokenAddress).transferFrom(
                address(this),
                prizes[i].owner,
                prizes[i].tokenId
            );
        }
        delete raffles[raffleId];
    }

    /**
     * @notice buy ticket with erc20
     * @param raffleId the id of the raffle to buy ticket for
     * @param ticketCount the number of tickets to buy
     */
    function buyTickets(uint256 raffleId, uint96 ticketCount) public {
        // transfer payment token frm account
        uint256 cost = raffles[raffleId].ticketPrice * ticketCount;
        IERC20(raffles[raffleId].paymentToken).transferFrom(
            msg.sender,
            address(this),
            cost
        );
        // give tickets to account
        _sendTicket(msg.sender, raffleId, ticketCount);
    }

    /**
     * @notice buy ticket with ETH
     * @param raffleId the id of the raffle to buy ticket for
     * @param ticketCount the number of tickets to buy
     */
    function buyTicketsEth(uint256 raffleId, uint96 ticketCount)
        public
        payable
    {
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
    function claimPrize(
        address to,
        uint256 raffleId,
        uint256 prizeIndex,
        uint256 ticketPurchaseIndex
    ) public {
        require(raffles[raffleId].seed != 0, "Winner not set");
        require(
            to == raffleTickets[raffleId][ticketPurchaseIndex].owner,
            "Not ticket owner"
        );
        uint256 ticketId = getWinnerTicketId(raffleId, prizeIndex);
        uint96 startId = raffleTickets[raffleId][ticketPurchaseIndex - 1].endId;
        uint96 endId = raffleTickets[raffleId][ticketPurchaseIndex].endId;
        require(
            ticketId >= startId && ticketId < endId,
            "Ticket id out of winner range"
        );
        rafflePrizes[raffleId][prizeIndex].claimed = true;
        IERC721(rafflePrizes[raffleId][prizeIndex].tokenAddress).transferFrom(
            address(this),
            to,
            rafflePrizes[raffleId][prizeIndex].tokenId
        );
    }

    /**
     * @notice claim share of sales for providing prize
     * @param account the account to claim the share of sales for
     * @param raffleId the id of the raffle to claim share of sales for
     */
    function claimSales(address account, uint256 raffleId) public {
        uint256 amount = getAccountTokenClaimAmount(account, raffleId);
        require(raffles[raffleId].seed != 0, "Winner not set");
        require(amount > 0, "No sales to claim");
        if (raffles[raffleId].paymentToken == address(0)) {
            (bool sent, ) = account.call{value: amount}("");
            require(sent, "Failed to send funds");
        } else {
            IERC20(raffles[raffleId].paymentToken).transferFrom(
                address(this),
                account,
                amount
            );
        }
    }

    /**
     * Initialize seed for raffle
     */
    function initializeSeed(uint256 raffleId) public {
        Raffle memory raffle = raffles[raffleId];
        require(raffle.endTimestamp < block.timestamp, "Raffle has not ended");
        require(raffle.seed == 0, "Seed already initialized");
        // uint224 royaltyAmount = uint224(getRoyaltyAmount(raffleId));
        // accumulateRoyalty(raffle.paymentToken, royaltyAmount);
        fakeRequestRandomWords(raffleId);
    }

    function accumulateRoyalty(address tokenAddress, uint224 amount) internal {
        uint256 index = royaltyPriceIndices[tokenAddress].length;
        blockNumberToIndex[tokenAddress][block.number] = index;
        uint224 cumulativeRoyalty = royaltyPriceIndices[tokenAddress][index - 1]
            .value + amount;
        royaltyPriceIndices[tokenAddress].push(
            RoyaltyPriceIndex({
                blockNumber: uint32(block.number),
                value: cumulativeRoyalty
            })
        );
    }

    /**
     * Fake chainlink request
     */
    function fakeRequestRandomWords(uint256 raffleId) internal {
        // generate pseudo random words
        bytes32 requestId = bytes32(abi.encodePacked(block.number));
        requestIdToRaffleId[requestId] = raffleId;
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = uint256(keccak256(abi.encodePacked(block.timestamp)));
        fulfillRandomWords(requestId, randomWords);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomWords(bytes32 requestId, uint256[] memory randomWords)
        internal
    {
        // TODO replace with chainlink
        uint256 raffleId = requestIdToRaffleId[requestId];
        raffles[raffleId].seed = uint96(randomWords[0]);
    }

    /**
     * @dev sends ticket to account
     * @param to the account to send ticket to
     * @param raffleId the id of the raffle to send ticket for
     * @param ticketCount the number of tickets to send
     */
    function _sendTicket(
        address to,
        uint256 raffleId,
        uint96 ticketCount
    ) internal {
        uint256 purchases = raffleTickets[raffleId].length;
        uint96 ticketEndId = purchases > 0
            ? raffleTickets[raffleId][purchases - 1].endId + ticketCount
            : ticketCount;
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
    function getPoolPrizeTokenConfig(uint256 raffleId, address prizeToken)
        public
        view
        returns (PoolPrizeTokenConfig memory config)
    {
        // NOTE consider changing config array to weight map for cheaper reads
        PoolPrizeTokenConfig[] memory configs = rafflePoolPrizeTokenConfigs[
            raffleId
        ];
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
    function getWinner(uint256 raffleId, uint256 prizeIndex)
        public
        view
        returns (address winner)
    {
        uint256 ticketId = getWinnerTicketId(raffleId, prizeIndex);
        uint256 ticketPurchaseIndex = getTicketPurchaseIndex(
            raffleId,
            ticketId
        );
        return raffleTickets[raffleId][ticketPurchaseIndex].owner;
    }

    function getAccountTokenClaimAmount(address account, uint256 raffleId)
        public
        view
        returns (uint256 amount)
    {
        // NOTE may overflow
        return
            (raffleAccountWeights[raffleId][account] *
                getClaimableAmount(raffleId)) / raffles[raffleId].totalWeight;
    }

    /**
     * @notice get total royalty amount from sales
     * @param raffleId the id of the raffle to get total royalty amount for
     * @return royaltyAmount the total royalty amount from sales
     */
    function getRoyaltyAmount(uint256 raffleId)
        public
        view
        returns (uint256 royaltyAmount)
    {
        uint256 totalSales = getTotalSales(raffleId);
        uint256 minimumSales = getMinimumSales(raffleId);
        return
            minimumSales *
            baseRoyalty +
            overflowRoyalty *
            (totalSales - minimumSales);
    }

    /**
     * @notice get total claimable sales (sales - royalty)
     * @param raffleId the id of the raffle to get total claimable sales for
     * @return claimableAmount the total claimable sales
     */
    function getClaimableAmount(uint256 raffleId)
        public
        view
        returns (uint256 claimableAmount)
    {
        uint256 totalSales = getTotalSales(raffleId);
        uint256 minimumSales = getMinimumSales(raffleId);
        return
            (10000 - baseRoyalty) *
            baseRoyalty +
            (10000 - overflowRoyalty) *
            (totalSales - minimumSales);
    }

    function getTotalSales(uint256 raffleId)
        public
        view
        returns (uint256 totalSales)
    {
        return
            raffleTickets[raffleId][raffleTickets[raffleId].length - 1].endId *
            raffles[raffleId].ticketPrice;
    }

    function getMinimumSales(uint256 raffleId)
        public
        view
        returns (uint256 minimumSales)
    {
        return
            (raffles[raffleId].minTickets *
                raffles[raffleId].ticketPrice *
                raffles[raffleId].totalWeight) / 10000;
    }

    /**
     * @dev binary search for ticket purchase index of ticketId
     * @param raffleId the id of the raffle to get winner for
     * @param ticketId the id of the ticket to get index for
     * @return ticketPurchaseIndex the purchase index of the ticket
     */
    function getTicketPurchaseIndex(uint256 raffleId, uint256 ticketId)
        public
        view
        returns (uint256 ticketPurchaseIndex)
    {
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
    function getWinnerTicketId(uint256 raffleId, uint256 prizeIndex)
        public
        view
        returns (uint256 ticketId)
    {
        // add salt to seed
        ticketId =
            uint256(keccak256((abi.encode(raffleId, prizeIndex)))) %
            rafflePrizes[raffleId].length;
    }

    /*
    OWNER FUNCTIONS
    */

    function setBaseRoyalty(uint256 _baseRoyalty) public onlyOwner {
        require(_baseRoyalty <= 10000, "Royalty must be <= 10000");
        baseRoyalty = _baseRoyalty;
    }

    function setOverflowRoyalty(uint256 _overflowRoyalty) public onlyOwner {
        require(_overflowRoyalty <= 10000, "Royalty must be <= 10000");
        overflowRoyalty = _overflowRoyalty;
    }

    /*
    MODIFIERS
    */
}

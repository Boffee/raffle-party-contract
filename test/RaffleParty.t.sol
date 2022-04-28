// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./mock/CheatCodes.sol";
import "./mock/DummyERC721.sol";
import "./mock/DummyERC20.sol";
import "../src/RaffleParty.sol";
import "forge-std/console.sol";

contract RafflePartyTest is CheatCodesDSTest {
    RaffleParty rp;

    DummyERC721 nft1;
    DummyERC721 nft2;
    DummyERC721 nft3;

    DummyERC20 t1;
    DummyERC20 t2;
    DummyERC20 t3;

    uint256 constant PRICE = 100e18;
    uint96 constant MIN_TICKETS = 100;
    uint256 constant DURATION = 100;

    address a1 = 0x0000000000000000000000000000000000000001;
    address a2 = 0x0000000000000000000000000000000000000002;
    address a3 = 0x0000000000000000000000000000000000000003;

    function setUp() public {
        nft1 = new DummyERC721();
        nft2 = new DummyERC721();
        nft3 = new DummyERC721();
        t1 = new DummyERC20();
        t2 = new DummyERC20();
        t3 = new DummyERC20();
        rp = new RaffleParty();
        mintTokens();
    }

    function testCreateRaffle() public {
        nft1.setApprovalForAll(address(rp), true);
        uint256 raffleId = rp.createRaffle(
            address(nft1),
            1,
            address(t1),
            uint48(block.timestamp),
            uint48(block.timestamp + 100),
            100e18,
            100,
            new address[](0),
            new uint64[](0)
        );
        assertEq(raffleId, 0);
    }

    function testBuyTickets() public {
        uint256 raffleId = createDummyRaffle();
        t1.approve(address(rp), PRICE * 100);
        rp.buyTickets(raffleId, 5);
        assertEq(t1.balanceOf(address(rp)), PRICE * 5);
    }

    function testInitializeSeed() public {
        uint256 raffleId = createDummyRaffle();
        t1.approve(address(rp), PRICE * 100);
        rp.buyTickets(raffleId, MIN_TICKETS);
        cheats.warp(block.timestamp + DURATION + 1);
        rp.initializeSeed(raffleId);
    }

    function testFailInitializeSeed1() public {
        uint256 raffleId = createDummyRaffle();
        t1.approve(address(rp), PRICE * 100);
        rp.buyTickets(raffleId, MIN_TICKETS);
        cheats.warp(block.timestamp + DURATION);
        rp.initializeSeed(raffleId);
    }

    function testFailInitializeSeed2() public {
        uint256 raffleId = createDummyRaffle();
        t1.approve(address(rp), PRICE * 99);
        rp.buyTickets(raffleId, MIN_TICKETS);
        cheats.warp(block.timestamp + DURATION + 1);
        rp.initializeSeed(raffleId);
    }

    function testClaimPrize() public {
        uint256 raffleId = createDummyRaffle();
        t1.approve(address(rp), PRICE * 100);
        rp.buyTickets(raffleId, MIN_TICKETS);
        cheats.warp(block.timestamp + DURATION + 1);
        rp.initializeSeed(raffleId);
        uint256 prizeIndex = 0;
        uint256 ticketId = rp.getWinnerTicketId(raffleId, prizeIndex);
        address winner = rp.getWinner(raffleId, prizeIndex);
        uint256 ticketPurchaseIndex = rp.getTicketPurchaseIndex(
            raffleId,
            ticketId
        );
        rp.claimPrize(winner, raffleId, prizeIndex, ticketPurchaseIndex);
        assertEq(nft1.ownerOf(0), winner);
    }

    function testBuyTicketsEth() public {
        uint256 raffleId = createDummyRaffleEth();
        rp.buyTicketsEth{value: PRICE * 5}(raffleId, 5);
        assertEq(address(rp).balance, PRICE * 5);
    }

    function createDummyRaffle() public returns (uint256 raffleId) {
        nft1.setApprovalForAll(address(rp), true);
        address[] memory poolPrizeTokens = new address[](1);
        poolPrizeTokens[0] = address(nft2);
        uint64[] memory poolPrizeTokenWeights = new uint64[](1);
        poolPrizeTokenWeights[0] = 5000;
        raffleId = rp.createRaffle(
            address(nft1),
            1,
            address(t1),
            uint48(block.timestamp),
            uint48(block.timestamp + DURATION),
            PRICE,
            MIN_TICKETS,
            poolPrizeTokens,
            poolPrizeTokenWeights
        );
    }

    function createDummyRaffleEth() public returns (uint256 raffleId) {
        nft1.setApprovalForAll(address(rp), true);
        raffleId = rp.createRaffle(
            address(nft1),
            1,
            address(0),
            uint48(block.timestamp),
            uint48(block.timestamp + DURATION),
            PRICE,
            MIN_TICKETS,
            new address[](0),
            new uint64[](0)
        );
    }

    function mintTokens() public {
        nft1.mint(address(this), 3);
        nft1.mint(a1, 3);
        nft1.mint(a2, 3);
        nft1.mint(a3, 3);
        nft2.mint(address(this), 3);
        nft2.mint(a1, 3);
        nft2.mint(a2, 3);
        nft2.mint(a3, 3);
        nft3.mint(address(this), 3);
        nft3.mint(a1, 3);
        nft3.mint(a2, 3);
        nft3.mint(a3, 3);
        t1.mint(address(this), 1000000e18);
        t1.mint(a1, 1000000e18);
        t1.mint(a2, 1000000e18);
        t1.mint(a3, 1000000e18);
        t2.mint(address(this), 1000000e18);
        t2.mint(a1, 1000000e18);
        t2.mint(a2, 1000000e18);
        t2.mint(a3, 1000000e18);
        t3.mint(address(this), 1000000e18);
        t3.mint(a1, 1000000e18);
        t3.mint(a2, 1000000e18);
        t3.mint(a3, 1000000e18);
    }
}

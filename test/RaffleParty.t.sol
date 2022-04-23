// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./mock/CheatCodes.sol";
import "./mock/DummyERC721.sol";
import "./mock/DummyERC20.sol";
import "../src/RaffleParty.sol";

contract RafflePartyTest is CheatCodesDSTest {
    RaffleParty rp;

    DummyERC721 nft1;
    DummyERC721 nft2;
    DummyERC721 nft3;

    DummyERC20 t1;
    DummyERC20 t2;
    DummyERC20 t3;

    address a1 = 0x0000000000000000000000000000000000000001;
    address a2 = 0x0000000000000000000000000000000000000002;
    address a3 = 0x0000000000000000000000000000000000000003;

    function setUp() public {
        nft1 = new DummyERC721();
        nft2 = new DummyERC721();
        nft3 = new DummyERC721();
        rp = new RaffleParty();
    }

    function testCreateRaffle() public {
        mintTokens();
        nft1.setApprovalForAll(address(rp), true);
        uint256 raffleId = rp.createRaffle(
            address(nft1),
            1,
            address(t1),
            uint48(block.timestamp),
            uint48(block.timestamp + 100),
            100e18,
            100
        );
        assertEq(raffleId, 0);
    }

    function createAndStartRaffle() public {}

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
    }
}

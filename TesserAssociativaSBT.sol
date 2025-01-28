// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract MegoTicketsSoulbound is ERC721, Ownable {
    struct Ticket {
        bool exists;
        string name;
        string description;
        string image;
        uint16 numMinted;
        address owner;
        bool soulbound;
    }

    uint256 private _tokenIdCounter;

    mapping(string => Ticket) public _tickets;
    mapping(uint256 => string) public _idToTier;
    mapping(uint256 => string) public _idToSerial;
    mapping(uint256 => bool) public _burned;
    mapping(address => bool) public _proxies;
    mapping(address => bool) public _owners; // Multi-owner support
    mapping(uint256 => uint256) public validUntil; // Stores the expiry timestamp for each token

    event Minted(uint256 indexed tokenId);
    event Claimed(uint256 indexed tokenId);
    event Burned(uint256 indexed tokenId);
    event OwnerAdded(address indexed newOwner);
    event OwnerRemoved(address indexed removedOwner);

    constructor(
        string memory _name,
        string memory _ticker
    ) ERC721(_name, _ticker) {
        _owners[msg.sender] = true; // Add the contract deployer as an initial owner
    }

    // Modifier for multiple owners
    modifier onlyOwners() {
        require(_owners[msg.sender], "MegoTicketsSoulbound: Caller is not an owner");
        _;
    }

    // Add a new owner
    function addOwner(address newOwner) external onlyOwners {
        _owners[newOwner] = true;
        emit OwnerAdded(newOwner);
    }

    // Remove an existing owner
    function removeOwner(address owner) external onlyOwners {
        require(owner != msg.sender, "MegoTicketsSoulbound: Cannot remove yourself");
        _owners[owner] = false;
        emit OwnerRemoved(owner);
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }

    function tokensOfOwner(
        address _owner
    )
        external
        view
        returns (uint256[] memory ownerTokens, string[] memory tierTokens)
    {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            return (new uint256[](0), new string[](0));
   } else {
            uint256[] memory result = new uint256[](tokenCount);
            string[] memory tiers = new string[](tokenCount);
            uint256 totalTkns = totalSupply();
            uint256 resultIndex = 0;
            uint256 tknId;

            for (tknId = 1; tknId <= totalTkns; tknId++) {
                if (!_burned[tknId] && ownerOf(tknId) == _owner) {
                    result[resultIndex] = tknId;
                    tiers[resultIndex] = _idToTier[tknId];
                    resultIndex++;
                }
            }

            return (result, tiers);
        }
    }

    function setProxyAddress(address proxy, bool state) external onlyOwners {
        _proxies[proxy] = state;
    }

    function manageTickets(
        string memory tier,
        address owner,
        string memory name,
        string memory description,
        string memory image,
        bool soulbound
    ) external {
        require(_proxies[msg.sender], "Can't manage tiers.");
        _tickets[tier].owner = owner;
        _tickets[tier].exists = true;
        _tickets[tier].name = name;
        _tickets[tier].description = description;
        _tickets[tier].image = image;
        _tickets[tier].soulbound = soulbound;
    }

    function returnMinted(string memory tier) external view returns (uint16) {
        Ticket memory ticket = _tickets[tier];
        return ticket.numMinted;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        string memory tier = _idToTier[id];
        Ticket memory ticket = _tickets[tier];
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "',
                        ticket.name,
                        " #",
                        _idToSerial[id],
                        '", "description": "',
                        ticket.description,
                        '", "image": "',
                        ticket.image,
                        '", "attributes": [',
                        '{"trait_type": "TIER", "value": "',
                        tier,
                        '"},',
                        '{"trait_type": "VALID_UNTIL", "value": "',
                        Strings.toString(validUntil[id]),
                        '"}',
                        "]}"
                    )
                )
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function mint(
        address receiver,
        string memory tier,
        uint256 amount
    ) external {
        require(
            _proxies[msg.sender],
            "MegoTicketsSoulbound: Only proxy can mint"
        );
        require(
            _tickets[tier].exists,
            "MegoTicketsSoulbound: Minting a non-existent tier"
        );

        Ticket storage ticket = _tickets[tier];

        for (uint256 k = 0; k < amount; k++) {
            _tokenIdCounter += 1;
            uint256 tokenId = _tokenIdCounter;
            ticket.numMinted++;
            _idToSerial[tokenId] = Strings.toString(ticket.numMinted);
            _idToTier[tokenId] = tier;
            validUntil[tokenId] = block.timestamp + 365 days; // Set expiration
            _safeMint(receiver, tokenId);
            emit Minted(tokenId);
        }
    }

    function burn(uint256 tokenId) public {
        require(
            _proxies[msg.sender] || ownerOf(tokenId) == msg.sender,
            "MegoTicketsSoulbound: Only proxy or owner can burn"
        );
        require(!_burned[tokenId], "MegoTicketsSoulbound: Already burned");
        _burned[tokenId] = true;
        _idToSerial[tokenId] = "";
        _idToTier[tokenId] = "";
        _burn(tokenId);
        emit Burned(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        string memory tier = _idToTier[tokenId];
        require(
            !_tickets[tier].soulbound || from == address(0) || _burned[tokenId],
            "MegoTicketsSoulbound: Can't transfer soulbound ticket"
        );
        super._beforeTokenTransfer(from, to, tokenId);
    }
}

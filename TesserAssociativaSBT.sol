// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract SpaghettETHImpactAssociati is ERC721, Ownable, Pausable {
    struct Ticket {
        bool exists;
        string name;
        string description;
        string image;
        uint16 numMinted;
        uint256 validUntil; // Expiration timestamp
        address owner;
        bool soulbound; // Indicates if the ticket is non-transferable
    }

    uint256 private _tokenIdCounter;

    mapping(string => Ticket) public _tickets;
    mapping(uint256 => string) public _idToTier;
    mapping(uint256 => string) public _idToSerial;
    mapping(uint256 => bool) public _burned;
    mapping(address => bool) public _proxies;
    mapping(address => bool) public onlyOwnerAddresses; // Extended OnlyOwner permissions

    bool public isPaused = false;

    event Minted(uint256 indexed tokenId, uint256 validUntil, bool soulbound);
    event Burned(uint256 indexed tokenId);

    modifier onlyOwners() {
        require(
            owner() == msg.sender || onlyOwnerAddresses[msg.sender],
            "Caller is not an owner"
        );
        _;
    }

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
        Ownable(msg.sender)
    {}

    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }

    function tokensOfOwner(address _owner)
        external
        view
        returns (uint256[] memory ownerTokens, string[] memory tierTokens)
    {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            return ([], []);
   } else {
            uint256[] memory result = new uint256[](tokenCount);
            string[] memory tiers = new string[](tokenCount);
            uint256 totalTkns = totalSupply();
            uint256 resultIndex = 0;
            uint256 tnkId;

            for (tnkId = 1; tnkId <= totalTkns; tnkId++) {
                if (!_burned[tnkId] && ownerOf(tnkId) == _owner) {
                    result[resultIndex] = tnkId;
                    tiers[resultIndex] = _idToTier[tnkId];
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
        require(
            _proxies[msg.sender],
            "Can't manage tiers."
        );
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
                        '"}, {"trait_type": "Soulbound", "value": "',
                        ticket.soulbound ? "true" : "false",
                        '"}, {"trait_type": "Valid Until", "value": "',
                        Strings.toString(ticket.validUntil),
                        '"}',
                        "]}"
                    )
                )
            )
        );
        string memory output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );
        return output;
    }

    function mint(
        address receiver,
        string memory tier,
        uint256 amount,
        bool soulbound
    ) external {
        require(_proxies[msg.sender], "SpaghettETH: Only proxy can mint");
        require(
            _tickets[tier].exists,
            "SpaghettETH: Minting a non-existent tier"
        );

        Ticket storage ticket = _tickets[tier];

        for (uint256 k = 0; k < amount; k++) {
            _tokenIdCounter += 1;
            uint256 tokenId = _tokenIdCounter;
            ticket.numMinted++;
            _idToSerial[tokenId] = Strings.toString(ticket.numMinted);
            _idToTier[tokenId] = tier;
            ticket.soulbound = soulbound;

            // Set validUntil as block.timestamp + 1 year
            ticket.validUntil = block.timestamp + 365 days;

            _safeMint(receiver, tokenId);

            emit Minted(tokenId, ticket.validUntil, soulbound);
        }
    }

    function burn(uint256 tokenId) public {
        require(
            _proxies[msg.sender] || ownerOf(tokenId) == msg.sender,
            "SpaghettETH: Only proxy or owner can burn"
        );
        require(!_burned[tokenId], "SpaghettETH: Already burned");
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
            "SpaghettETH: Can't transfer soulbound ticket"
        );
        super._beforeTokenTransfer(from, to, tokenId);
    }
}


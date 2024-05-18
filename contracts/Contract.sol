// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Kokuhaku is ERC721, ERC721Enumerable, ERC721Pausable, ERC721Burnable, ERC2981, Ownable {

    // ✧･ﾟ: *✧･ﾟ:* 1. Custom Error Definitions ✧･ﾟ: *✧･ﾟ:*
    error NotOnWhiteList();
    error FreeMintUsed();
    error NotEnoughFunds();
    error CannotMintZeroTokens();
    error ExceedsMaxSupply();
    error NoTokensAvailable();
    error TransferFailed();
    error CallerNotOwnerNorApproved();
    error NonexistentToken();

    // ✧･ﾟ: *✧･ﾟ:* 2. Property Variables ✧･ﾟ: *✧･ﾟ:*
    uint96 public maxSupply = 20000;
    string public baseURI;
    string public contractURI;
    uint256 private _nextTokenId;
    mapping(uint256 => string) private tokenURIs;
    mapping(uint256 => bool) private envelopeOpened;
    mapping (address => bool) public whiteList;
    mapping(address => bool) public freeMintUsed;

    // ✧･ﾟ: *✧･ﾟ:* 3. Constructor ✧･ﾟ: *✧･ﾟ:*
    constructor (
        address initialOwner, 
        uint96 feeNumerator,
        string memory _initBaseURI,
        string memory _contractURI
    )
    ERC721("Kokuhaku", "KOKU") Ownable(initialOwner) {
        _setDefaultRoyalty(msg.sender, feeNumerator);
        baseURI = _initBaseURI;
        contractURI = _contractURI;
        _nextTokenId++;
    }

    // ✧･ﾟ: *✧･ﾟ:* 4. Owner Functions ✧･ﾟ: *✧･ﾟ:*
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setContractURI(string calldata _contractURI) public onlyOwner {
        contractURI = _contractURI;
    }

    function resetRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function withdraw(address _addr) external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(_addr).call{value: balance}("");
        if (!success) revert TransferFailed();
    }

    function setWhiteList(address[] calldata addresses) external onlyOwner {
        for(uint256 i = 0; i < addresses.length; i++) {
            whiteList[addresses[i]] = true;
        }
    }

    // ✧･ﾟ: *✧･ﾟ:* 5. Minting Functions ✧･ﾟ: *✧･ﾟ:*
    function privateMint() public {
        if (!whiteList[msg.sender]) revert NotOnWhiteList();
        if (freeMintUsed[msg.sender]) revert FreeMintUsed();
        mint(msg.sender);
        freeMintUsed[msg.sender] = true;
    }

    function publicMint() public payable {
        if (msg.value < 1.00 ether) revert NotEnoughFunds();
        mint(msg.sender);
    }

    function batchMint(uint256 amount) public payable {
        if (amount == 0) revert CannotMintZeroTokens();
        if (totalSupply() + amount > maxSupply) revert ExceedsMaxSupply();
        if (msg.value < 1.00 ether * amount) revert NotEnoughFunds();

        for (uint256 i = 0; i < amount; i++) {
            mint(msg.sender);
        }
    }

    function airdropMint(address[] calldata recipients) external onlyOwner {
        if (totalSupply() + recipients.length > maxSupply) revert ExceedsMaxSupply();

        for (uint256 i = 0; i < recipients.length; i++) {
            mint(recipients[i]);
        }
    }

    function mint(address to) internal {
        if (totalSupply() >= maxSupply) revert NoTokensAvailable();
        uint256 tokenId = _nextTokenId;
        _safeMint(to, tokenId);
        tokenURIs[tokenId] = string.concat(baseURI, "closed_", Strings.toString(_nextTokenId++), ".json");
    }

    // ✧･ﾟ: *✧･ﾟ:* 6. Transfer Functions ✧･ﾟ: *✧･ﾟ:*
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
        if (!_isAuthorized(from, msg.sender, tokenId)) revert CallerNotOwnerNorApproved();
        openEnvelope(tokenId);
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override(ERC721, IERC721) {
        if (!_isAuthorized(from, msg.sender, tokenId)) revert CallerNotOwnerNorApproved();
        openEnvelope(tokenId);
        super.safeTransferFrom(from, to, tokenId, data);
    }

    // ✧･ﾟ: *✧･ﾟ:* 7. Other Functions ✧･ﾟ: *✧･ﾟ:*
    function burn(uint256 tokenId) public override {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function openEnvelope(uint256 tokenId) private {
        if (!envelopeOpened[tokenId]) {
            tokenURIs[tokenId] = string.concat(baseURI, "open_", Strings.toString(tokenId), ".json");
            envelopeOpened[tokenId] = true;
        }
    }

    // ✧･ﾟ: *✧･ﾟ:* 8. Mandatory Overrides ✧･ﾟ: *✧･ﾟ:*
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable, ERC721Pausable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (ERC721.ownerOf(tokenId) == address(0)) revert NonexistentToken();
        return tokenURIs[tokenId];
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
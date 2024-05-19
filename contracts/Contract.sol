// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Kokuhaku NFT Contract
/// @notice This contract implements an ERC721 NFT with minting, burning, pausing, and royalty functionalities.
contract Kokuhaku is ERC721, ERC721Enumerable, ERC721Pausable, ERC721Burnable, ERC2981, Ownable {

    // ✧･ﾟ: *✧･ﾟ:* 1. Custom Error Definitions ✧･ﾟ: *✧･ﾟ:*
    error NotOnWhiteList();
    error NotEnoughFunds();
    error CannotMintZeroTokens();
    error ExceedsMaxSupply();
    error NoTokensAvailable();
    error TransferFailed();
    error CallerNotOwnerNorApproved();
    error NonexistentToken();
    error ExceedsBatchLimit();

    // ✧･ﾟ: *✧･ﾟ:* 2. Property Variables ✧･ﾟ: *✧･ﾟ:*
    /// @notice Maximum supply of tokens.
    uint96 public maxSupply = 20000;
    /// @notice Base URI for token metadata.
    string public baseURI;
    /// @notice URI for the contract metadata.
    string public contractURI;
    /// @dev Internal counter for the next token ID.
    uint256 private _nextTokenId;
    /// @dev Mapping to track if an envelope is opened.
    mapping(uint256 => bool) private envelopeOpened;
    /// @notice Mapping to track the whitelist status of addresses.
    mapping(address => bool) public whiteList;

    // ✧･ﾟ: *✧･ﾟ:* 3. Constructor ✧･ﾟ: *✧･ﾟ:*
    /// @notice Constructor to initialize the contract with initial values.
    /// @param initialOwner Address of the initial owner of the contract.
    /// @param feeNumerator Royalty fee numerator.
    /// @param _initBaseURI Initial base URI for token metadata.
    /// @param _contractURI URI for the contract metadata.
    constructor (
        address initialOwner, 
        uint96 feeNumerator,
        string memory _initBaseURI,
        string memory _contractURI
    ) payable ERC721("Kokuhaku", "KOKU") Ownable(initialOwner) {
        require(initialOwner != address(0), "Invalid owner address");
        require(feeNumerator <= _feeDenominator(), "Invalid fee numerator");
        require(bytes(_initBaseURI).length > 0, "Base URI cannot be empty");
        require(bytes(_contractURI).length > 0, "Contract URI cannot be empty");

        baseURI = _initBaseURI;
        contractURI = _contractURI;
        unchecked { _nextTokenId++; }
    }

    // ✧･ﾟ: *✧･ﾟ:* 4. Owner Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Function to pause the contract.
    /// @dev Can only be called by the owner.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Function to unpause the contract.
    /// @dev Can only be called by the owner.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Function to set the contract URI.
    /// @dev Can only be called by the owner.
    /// @param _contractURI New contract URI.
    function setContractURI(string calldata _contractURI) external onlyOwner {
        contractURI = _contractURI;
    }

    /// @notice Function to reset the royalty information.
    /// @dev Can only be called by the owner.
    /// @param receiver Address to receive the royalties.
    /// @param feeNumerator Royalty fee numerator.
    function resetRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @notice Function to withdraw the contract's balance to a specified address.
    /// @dev Can only be called by the owner.
    /// @param _addr Address to receive the withdrawn balance.
    function withdraw(address _addr) external onlyOwner {
        (bool success, ) = payable(_addr).call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Function to set the whitelist addresses.
    /// @dev Can only be called by the owner.
    /// @param addresses Array of addresses to be whitelisted.
    function setWhiteList(address[] calldata addresses) external onlyOwner {
        uint256 length = addresses.length;
        for (uint256 i = 0; i < length; i++) {
            whiteList[addresses[i]] = true;
        }
    }

    // ✧･ﾟ: *✧･ﾟ:* 5. Minting Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Function for whitelisted addresses to mint a token for free.
    /// @dev Only whitelisted addresses can call this function. 
    function privateMint() external {
        if (!whiteList[msg.sender]) revert NotOnWhiteList();
        if (totalSupply() >= maxSupply) revert ExceedsMaxSupply();  // Check maxSupply
        delete whiteList[msg.sender];
        mint(msg.sender);
        emit FreeMintUsed(msg.sender);
    }

    /// @notice Function for public to mint a token with a fee.
    /// @dev Requires payment of 1 ether.
    function publicMint() external payable {
        if (msg.value != 1.00 ether) revert NotEnoughFunds();
        if (totalSupply() >= maxSupply) revert ExceedsMaxSupply();
        mint(msg.sender);
    }

    /// @notice Function for batch minting of tokens.
    /// @dev Requires payment of 1 ether per token and a maximum of 10 tokens can be minted in a single batch.
    /// @param amount Number of tokens to mint.
    function batchMint(uint256 amount) external payable {
        if (amount == 0) revert CannotMintZeroTokens();
        if (amount > 10) revert ExceedsBatchLimit();
        if (totalSupply() + amount > maxSupply) revert ExceedsMaxSupply();
        if (msg.value != 1.00 ether * amount) revert NotEnoughFunds();

        for (uint256 i = 0; i < amount; i++) {
            mint(msg.sender);
        }
    }

    /// @notice Function for the owner to mint tokens to multiple recipients.
    /// @dev Can only be called by the owner.
    /// @param recipients Array of addresses to receive the minted tokens.
    function airdropMint(address[] calldata recipients) external onlyOwner {
        uint256 recipientsLength = recipients.length;
        if (totalSupply() + recipientsLength > maxSupply) revert ExceedsMaxSupply();

        for (uint256 i = 0; i < recipientsLength; i++) {
            mint(recipients[i]);
        }
    }

    /// @notice Internal function to mint a token to a specified address.
    /// @param to Address to receive the minted token.
    function mint(address to) internal {
        if (totalSupply() >= maxSupply) revert NoTokensAvailable();
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    // ✧･ﾟ: *✧･ﾟ:* 6. Transfer Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Function to transfer a token from one address to another.
    /// @dev Overrides the default ERC721 implementation to include envelope opening logic.
    /// @param from Address transferring the token.
    /// @param to Address receiving the token.
    /// @param tokenId ID of the token being transferred.
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
        if (!_isAuthorized(from, msg.sender, tokenId)) revert CallerNotOwnerNorApproved();
        openEnvelope(tokenId);
        super.transferFrom(from, to, tokenId);
    }

    /// @notice Function to safely transfer a token from one address to another with additional data.
    /// @dev Overrides the default ERC721 implementation to include envelope opening logic.
    /// @param from Address transferring the token.
    /// @param to Address receiving the token.
    /// @param tokenId ID of the token being transferred.
    /// @param data Additional data sent with the transfer.
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override(ERC721, IERC721) {
        if (!_isAuthorized(from, msg.sender, tokenId)) revert CallerNotOwnerNorApproved();
        openEnvelope(tokenId);
        super.safeTransferFrom(from, to, tokenId, data);
    }

    // ✧･ﾟ: *✧･ﾟ:* 7. Other Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Function to burn a token.
    /// @dev Overrides the default ERC721 implementation.
    /// @param tokenId ID of the token to burn.
    function burn(uint256 tokenId) public override {
        super._burn(tokenId);
    }

    /// @notice Function to get the base URI for token metadata.
    /// @dev Overrides the default ERC721 implementation.
    /// @return Base URI string.
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /// @notice Internal function to open an envelope.
    /// @param tokenId ID of the token whose envelope is to be opened.
    function openEnvelope(uint256 tokenId) private {
        if (!envelopeOpened[tokenId]) {
            envelopeOpened[tokenId] = true;
        }
    }

    // ✧･ﾟ: *✧･ﾟ:* 8. Mandatory Overrides ✧･ﾟ: *✧･ﾟ:*
    /// @notice Internal function to update balances and other data.
    /// @dev Overrides multiple inherited functions.
    /// @param to Address receiving the token.
    /// @param tokenId ID of the token being transferred.
    /// @param auth Address authorized for the transfer.
    /// @return Address authorized for the transfer.
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable, ERC721Pausable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    /// @notice Function to get the token URI.
    /// @dev Overrides the default ERC721 implementation.
    /// @param tokenId ID of the token.
    /// @return Token URI string.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (ERC721.ownerOf(tokenId) == address(0)) revert NonexistentToken();
        return string.concat(baseURI, envelopeOpened[tokenId] ? "open_" : "closed_", Strings.toString(tokenId), ".json");
    }

    /// @notice Internal function to increase balance.
    /// @dev Overrides multiple inherited functions.
    /// @param account Address whose balance is to be increased.
    /// @param value Value by which the balance is to be increased.
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    /// @notice Function to check if the contract supports a given interface.
    /// @dev Overrides multiple inherited functions.
    /// @param interfaceId Interface identifier.
    /// @return Boolean indicating if the interface is supported.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ✧･ﾟ: *✧･ﾟ:* 9. Event Definitions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Event emitted when a free mint is used.
    /// @param user Address of the user who used the free mint.
    event FreeMintUsed(address indexed user);
}
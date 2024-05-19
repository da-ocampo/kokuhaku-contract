// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Kokuhaku NFT Contract
/// @notice This contract manages the minting, burning, pausing, and transferring of Kokuhaku NFTs
/// @dev Extends ERC721, ERC721Enumerable, ERC721Burnable, ERC721Pausable, ERC2981, Ownable
contract Kokuhaku is ERC721, ERC721Enumerable, ERC721Pausable, ERC721Burnable, ERC2981, Ownable {

    // ✧･ﾟ: *✧･ﾟ:* 1. Custom Error Definitions ✧･ﾟ: *✧･ﾟ:*
    /// @dev Error for when an address is not on the whitelist
    error NotOnWhiteList();
    /// @dev Error for when there are not enough funds for a transaction
    error NotEnoughFunds();
    /// @dev Error for when an attempt is made to mint zero tokens
    error CannotMintZeroTokens();
    /// @dev Error for when the maximum supply of tokens is exceeded
    error ExceedsMaxSupply();
    /// @dev Error for when there are no tokens available to mint
    error NoTokensAvailable();
    /// @dev Error for when a transfer fails
    error TransferFailed();
    /// @dev Error for when the caller is neither the owner nor approved for a token
    error CallerNotOwnerNorApproved();
    /// @dev Error for when a nonexistent token is accessed
    error NonexistentToken();
    /// @dev Error for when a batch mint exceeds the limit
    error ExceedsBatchLimit();

    // ✧･ﾟ: *✧･ﾟ:* 2. Property Variables ✧･ﾟ: *✧･ﾟ:*
    /// @notice Maximum supply of tokens
    uint96 public maxSupply = 20000;
    /// @notice Base URI for token metadata
    string public baseURI;
    /// @notice Contract URI for contract-level metadata
    string public contractURI;
    /// @dev Tracks the next token ID to be minted
    uint256 private _nextTokenId;
    /// @notice Mapping of token IDs to their URIs
    mapping(uint256 => string) public tokenURIs;
    /// @dev Mapping to track if an envelope has been opened
    mapping(uint256 => bool) private envelopeOpened;
    /// @notice Mapping of whitelisted addresses
    mapping(address => bool) public whiteList;

    // ✧･ﾟ: *✧･ﾟ:* 3. Constructor ✧･ﾟ: *✧･ﾟ:*
    /// @notice Initializes the contract with the given parameters
    /// @param initialOwner Address of the initial owner
    /// @param feeNumerator Royalty fee numerator
    /// @param _initBaseURI Initial base URI for token metadata
    /// @param _contractURI URI for contract-level metadata
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
    /// @notice Pauses the contract
    /// @dev Only callable by the owner
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract
    /// @dev Only callable by the owner
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Sets the contract URI
    /// @param _contractURI New contract URI
    /// @dev Only callable by the owner
    function setContractURI(string calldata _contractURI) external onlyOwner {
        contractURI = _contractURI;
    }

    /// @notice Resets the royalty information
    /// @param receiver Address to receive royalties
    /// @param feeNumerator Royalty fee numerator
    /// @dev Only callable by the owner
    function resetRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @notice Withdraws the contract balance to the specified address
    /// @param _addr Address to receive the withdrawn balance
    /// @dev Only callable by the owner
    function withdraw(address _addr) external onlyOwner {
        (bool success, ) = payable(_addr).call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Adds addresses to the whitelist
    /// @param addresses Array of addresses to be added to the whitelist
    /// @dev Only callable by the owner
    function setWhiteList(address[] calldata addresses) external onlyOwner {
        uint256 length = addresses.length;
        for (uint256 i = 0; i < length; i++) {
            whiteList[addresses[i]] = true;
        }
    }

    // ✧･ﾟ: *✧･ﾟ:* 5. Minting Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Mints a token to the sender if they are on the whitelist
    /// @dev Only callable by whitelisted addresses
    function privateMint() external {
        if (!whiteList[msg.sender]) revert NotOnWhiteList();
        if (totalSupply() >= maxSupply) revert ExceedsMaxSupply();
        delete whiteList[msg.sender];
        mint(msg.sender);
        emit FreeMintUsed(msg.sender);
    }

    /// @notice Mints a token to the sender for a fee
    /// @dev Requires a payment of 1 ether
    function publicMint() external payable {
        if (msg.value != 1.00 ether) revert NotEnoughFunds();
        if (totalSupply() >= maxSupply) revert ExceedsMaxSupply();
        mint(msg.sender);
    }

    /// @notice Mints multiple tokens to the sender for a fee
    /// @param amount Number of tokens to mint
    /// @dev Requires a payment of 1 ether per token, with a maximum batch size of 10
    function batchMint(uint256 amount) external payable {
        if (amount == 0) revert CannotMintZeroTokens();
        if (amount > 10) revert ExceedsBatchLimit();
        if (totalSupply() + amount > maxSupply) revert ExceedsMaxSupply();
        if (msg.value != 1.00 ether * amount) revert NotEnoughFunds();

        for (uint256 i = 0; i < amount; i++) {
            mint(msg.sender);
        }
    }

    /// @notice Airdrops tokens to the specified recipients
    /// @param recipients Array of recipient addresses
    /// @dev Only callable by the owner
    function airdropMint(address[] calldata recipients) external onlyOwner {
        uint256 recipientsLength = recipients.length;
        if (totalSupply() + recipientsLength > maxSupply) revert ExceedsMaxSupply();

        for (uint256 i = 0; i < recipientsLength; i++) {
            mint(recipients[i]);
        }
    }

    /// @dev Internal function to mint a token to the specified address
    /// @param to Address to receive the minted token
    function mint(address to) internal {
        if (totalSupply() >= maxSupply) revert NoTokensAvailable();
        uint256 tokenId = _nextTokenId;
        _safeMint(to, tokenId);
        tokenURIs[tokenId] = string.concat(baseURI, "closed_", Strings.toString(_nextTokenId++), ".json");
    }

    // ✧･ﾟ: *✧･ﾟ:* 6. Transfer Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Transfers a token from one address to another
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param tokenId ID of the token to transfer
    /// @dev Overrides ERC721 transferFrom and opens the envelope if it is closed
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
        if (!_isAuthorized(from, msg.sender, tokenId)) revert CallerNotOwnerNorApproved();
        openEnvelope(tokenId);
        super.transferFrom(from, to, tokenId);
    }

    /// @notice Safely transfers a token from one address to another
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param tokenId ID of the token to transfer
    /// @param data Additional data to include with the transfer
    /// @dev Overrides ERC721 safeTransferFrom and opens the envelope if it is closed
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override(ERC721, IERC721) {
        if (!_isAuthorized(from, msg.sender, tokenId)) revert CallerNotOwnerNorApproved();
        openEnvelope(tokenId);
        super.safeTransferFrom(from, to, tokenId, data);
    }

    // ✧･ﾟ: *✧･ﾟ:* 7. Other Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Burns a token
    /// @param tokenId ID of the token to burn
    /// @dev Overrides ERC721Burnable burn
    function burn(uint256 tokenId) public override {
        super._burn(tokenId);
    }

    /// @dev Returns the base URI for the token metadata
    /// @return The base URI string
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /// @dev Opens the envelope for the specified token ID
    /// @param tokenId ID of the token to open the envelope for
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

    // ✧･ﾟ: *✧･ﾟ:* 9. Event Definitions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Emitted when a free mint is used
    /// @param user Address of the user who used the free mint
    event FreeMintUsed(address indexed user);
}
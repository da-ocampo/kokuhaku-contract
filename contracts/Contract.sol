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
    uint96 public maxSupply = 20000;
    string public baseURI;
    string public contractURI;
    uint256 private _nextTokenId;
    mapping(uint256 => string) public tokenURIs;
    mapping(uint256 => bool) private envelopeOpened;
    mapping(address => bool) public whiteList;

    // ✧･ﾟ: *✧･ﾟ:* 3. Constructor ✧･ﾟ: *✧･ﾟ:*
    /// @notice Initializes the contract with the given parameters.
    /// @param initialOwner The initial owner of the contract.
    /// @param feeNumerator The royalty fee numerator.
    /// @param _initBaseURI The initial base URI for token metadata.
    /// @param _contractURI The URI for the contract metadata.
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
    /// @notice Pauses all token transfers.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses all token transfers.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Sets the contract URI.
    /// @param _contractURI The new contract URI.
    function setContractURI(string calldata _contractURI) external onlyOwner {
        contractURI = _contractURI;
    }

    /// @notice Resets the royalty information.
    /// @param receiver The address to receive the royalties.
    /// @param feeNumerator The royalty fee numerator.
    function resetRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @notice Withdraws the contract balance to the specified address.
    /// @param _addr The address to send the balance to.
    function withdraw(address _addr) external onlyOwner {
        (bool success, ) = payable(_addr).call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Adds addresses to the whitelist.
    /// @param addresses The array of addresses to add to the whitelist.
    function setWhiteList(address[] calldata addresses) external onlyOwner {
        uint256 length = addresses.length;
        for (uint256 i = 0; i < length; i++) {
            whiteList[addresses[i]] = true;
        }
    }

    // ✧･ﾟ: *✧･ﾟ:* 5. Minting Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Mints a token if the caller is whitelisted.
    function privateMint() external {
        if (!whiteList[msg.sender]) revert NotOnWhiteList();
        if (totalSupply() >= maxSupply) revert ExceedsMaxSupply();  // Check maxSupply
        delete whiteList[msg.sender];
        mint(msg.sender);
        emit FreeMintUsed(msg.sender);
    }

    /// @notice Mints a token for the caller if they send the required ETH.
    function publicMint() external payable {
        if (msg.value != 1.00 ether) revert NotEnoughFunds();
        if (totalSupply() >= maxSupply) revert ExceedsMaxSupply();
        mint(msg.sender);
    }

    /// @notice Mints multiple tokens for the caller if they send the required ETH.
    /// @param amount The number of tokens to mint.
    function batchMint(uint256 amount) external payable {
        if (amount == 0) revert CannotMintZeroTokens();
        if (amount > 10) revert ExceedsBatchLimit();
        if (totalSupply() + amount > maxSupply) revert ExceedsMaxSupply();
        if (msg.value != 1.00 ether * amount) revert NotEnoughFunds();

        for (uint256 i = 0; i < amount; i++) {
            mint(msg.sender);
        }
    }

    /// @notice Mints tokens for a list of recipients.
    /// @param recipients The array of addresses to receive the tokens.
    function airdropMint(address[] calldata recipients) external onlyOwner {
        uint256 recipientsLength = recipients.length;
        if (totalSupply() + recipientsLength > maxSupply) revert ExceedsMaxSupply();

        for (uint256 i = 0; i < recipientsLength; i++) {
            mint(recipients[i]);
        }
    }

    /// @dev Internal function to mint a token to a specified address.
    /// @param to The address to mint the token to.
    function mint(address to) internal {
        if (totalSupply() >= maxSupply) revert NoTokensAvailable();
        uint256 tokenId = _nextTokenId;
        _safeMint(to, tokenId);
        tokenURIs[tokenId] = string.concat(baseURI, "closed_", Strings.toString(_nextTokenId++), ".json");
    }

    // ✧･ﾟ: *✧･ﾟ:* 6. Transfer Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Transfers a token from one address to another.
    /// @param from The address to transfer the token from.
    /// @param to The address to transfer the token to.
    /// @param tokenId The ID of the token to transfer.
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
        if (!_isAuthorized(from, msg.sender, tokenId)) revert CallerNotOwnerNorApproved();
        openEnvelope(tokenId);
        super.transferFrom(from, to, tokenId);
    }

    /// @notice Safely transfers a token from one address to another.
    /// @param from The address to transfer the token from.
    /// @param to The address to transfer the token to.
    /// @param tokenId The ID of the token to transfer.
    /// @param data Additional data to send along with the transfer.
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override(ERC721, IERC721) {
        if (!_isAuthorized(from, msg.sender, tokenId)) revert CallerNotOwnerNorApproved();
        openEnvelope(tokenId);
        super.safeTransferFrom(from, to, tokenId, data);
    }

    // ✧･ﾟ: *✧･ﾟ:* 7. Other Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Burns a token, permanently removing it from the blockchain.
    /// @param tokenId The ID of the token to burn.
    function burn(uint256 tokenId) public override {
        super._burn(tokenId);
    }

    /// @dev Returns the base URI for the token metadata.
    /// @return The base URI string.
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /// @dev Opens the envelope of a token, changing its metadata URI.
    /// @param tokenId The ID of the token to open.
    function openEnvelope(uint256 tokenId) private {
        if (!envelopeOpened[tokenId]) {
            tokenURIs[tokenId] = string.concat(baseURI, "open_", Strings.toString(tokenId), ".json");
            envelopeOpened[tokenId] = true;
        }
    }

    // ✧･ﾟ: *✧･ﾟ:* 8. Mandatory Overrides ✧･ﾟ: *✧･ﾟ:*
    /// @dev See {ERC721-_update}.
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable, ERC721Pausable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    /// @dev Returns the metadata URI of a token.
    /// @param tokenId The ID of the token.
    /// @return The metadata URI string.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (ERC721.ownerOf(tokenId) == address(0)) revert NonexistentToken();
        return tokenURIs[tokenId];
    }

    /// @dev Increases the balance of an account.
    /// @param account The address of the account.
    /// @param value The amount to increase by.
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    /// @dev Returns true if the contract supports a given interface.
    /// @param interfaceId The ID of the interface to check.
    /// @return True if the interface is supported, false otherwise.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ✧･ﾟ: *✧･ﾟ:* 9. Event Definitions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Emitted when a user uses a free mint.
    /// @param user The address of the user who used the free mint.
    event FreeMintUsed(address indexed user);
}
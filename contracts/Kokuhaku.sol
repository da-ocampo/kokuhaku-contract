// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {ERC721, IERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IKokuhaku} from "./IKokuhaku.sol";

/// @title Kokuhaku NFT Contract
/// @notice This contract implements an ERC721 NFT with minting, burning, pausing, and royalty functionalities.
contract Kokuhaku is
    IKokuhaku,
    ERC721,
    ERC721Enumerable,
    ERC721Pausable,
    ERC721Burnable,
    ERC2981,
    Ownable
{
    using BitMaps for BitMaps.BitMap;

    // ✧･ﾟ: *✧･ﾟ:* 2. Property Variables ✧･ﾟ: *✧･ﾟ:*
    /// @notice Maximum supply of tokens.
    uint96 public constant maxSupply = 20000;

    /// @notice Base URI for token metadata.
    string public baseURI;

    /// @notice URI for the contract metadata.
    string public contractURI;

    /// @dev Internal counter for the next token ID.
    uint256 private _nextTokenId;

    BitMaps.BitMap internal envelopeOpened;

    /// @dev Mapping to track if an envelope is opened.
    // mapping(uint256 => bool) private envelopeOpened;

    /// @notice Mapping to track the whitelist status of addresses.
    mapping(address => bool) public whiteList;

    // ✧･ﾟ: *✧･ﾟ:* 3. Constructor ✧･ﾟ: *✧･ﾟ:*
    /// @notice Constructor to initialize the contract with initial values.
    /// @param initialOwner Address of the initial owner of the contract.
    /// @param feeNumerator Royalty fee numerator.
    /// @param _initBaseURI Initial base URI for token metadata.
    /// @param _contractURI URI for the contract metadata.
    constructor(
        address initialOwner,
        uint96 feeNumerator,
        string memory _initBaseURI,
        string memory _contractURI
    ) payable ERC721("Kokuhaku", "KOKU") Ownable(initialOwner) {
        if (initialOwner == address(0)) {
            revert ZeroAddressDisallowed();
        }

        require(feeNumerator <= _feeDenominator(), "Invalid fee numerator");

        if (bytes(_initBaseURI).length > 0) {
            revert EmptyUriDisallowed();
        }

        if (bytes(_contractURI).length > 0) {
            revert EmptyUriDisallowed();
        }

        baseURI = _initBaseURI;
        contractURI = _contractURI;

        _setDefaultRoyalty(initialOwner, feeNumerator);

        unchecked {
            _nextTokenId++;
        }
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
    function resetRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @notice Function to withdraw the contract's balance to a specified address.
    /// @dev Can only be called by the owner.
    /// @param _addr Address to receive the withdrawn balance.
    function withdraw(address _addr) external onlyOwner {
        bytes4 errorSelector = IKokuhaku.TransferFailed.selector;
        assembly {
            let success := call(gas(), _addr, selfbalance(), 0, 0, 0, 0)
            if iszero(success) {
                let ptr := mload(0x40)
                mstore(ptr, errorSelector)
                revert(ptr, 0x4)
            }
        }
    }

    /// @notice Function to set the whitelist addresses.
    /// @dev Can only be called by the owner.
    /// @param addresses Array of addresses to be whitelisted.
    function setWhiteList(address[] calldata addresses) external onlyOwner {
        uint256 length = addresses.length;
        for (uint256 i; i < length; i++) {
            whiteList[addresses[i]] = true;
        }
    }

    // ✧･ﾟ: *✧･ﾟ:* 5. Minting Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Function for whitelisted addresses to mint a token for free.
    /// @dev Only whitelisted addresses can call this function.
    function privateMint() external whenNotPaused {
        if (!whiteList[msg.sender]) revert NotOnWhiteList();

        if (totalSupply() == maxSupply) revert MintingExceedsMaxSupply();

        delete whiteList[msg.sender];
        mint(msg.sender);
        emit FreeMintUsed(msg.sender);
    }

    /// @notice Function for public to mint a token with a fee.
    /// @dev Requires payment of 1 ether.
    function publicMint() external payable whenNotPaused {
        if (msg.value != 1.00 ether) revert NotEnoughFunds();
        if (totalSupply() == maxSupply) revert MintingExceedsMaxSupply();
        mint(msg.sender);
    }

    /// @notice Function for batch minting of tokens.
    /// @dev Requires payment of 1 ether per token and a maximum of 10 tokens can be minted in a single batch.
    /// @param amount Number of tokens to mint.
    function batchMint(
        uint256 amount
    ) external payable whenNotPaused whenNotPaused {
        if (amount == 0) revert CannotMintZeroTokens();
        if (amount > 10) revert ExceedsBatchLimit();
        if (totalSupply() + amount > maxSupply)
            revert MintingExceedsMaxSupply();
        if (msg.value != 1.00 ether * amount) revert NotEnoughFunds();

        for (uint256 i; i < amount; i++) {
            mint(msg.sender);
        }
    }

    /// @notice Function for the owner to mint tokens to multiple recipients.
    /// @dev Can only be called by the owner.
    /// @param recipients Array of addresses to receive the minted tokens.
    function airdropMint(address[] calldata recipients) external onlyOwner {
        uint256 recipientsLength = recipients.length;
        if (totalSupply() + recipientsLength > maxSupply)
            revert MintingExceedsMaxSupply();

        for (uint256 i; i < recipientsLength; i++) {
            mint(recipients[i]);
        }
    }

    /// @notice Internal function to mint a token to a specified address.
    /// @param to Address to receive the minted token.
    function mint(address to) internal {
        _safeMint(to, _nextTokenId++);
    }

    // ✧･ﾟ: *✧･ﾟ:* 6. Transfer Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Function to transfer a token from one address to another.
    /// @dev Overrides the default ERC721 implementation to include envelope opening logic.
    /// @param from Address transferring the token.
    /// @param to Address receiving the token.
    /// @param tokenId ID of the token being transferred.
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721, IERC721) whenNotPaused {
        if (!_isAuthorized(from, msg.sender, tokenId))
            revert CallerNotOwnerNorApproved();
        openEnvelope(tokenId);
        super.transferFrom(from, to, tokenId);
    }

    /// @notice Function to safely transfer a token from one address to another with additional data.
    /// @dev Overrides the default ERC721 implementation to include envelope opening logic.
    /// @param from Address transferring the token.
    /// @param to Address receiving the token.
    /// @param tokenId ID of the token being transferred.
    /// @param data Additional data sent with the transfer.
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override(ERC721, IERC721) whenNotPaused {
        if (!_isAuthorized(from, msg.sender, tokenId))
            revert CallerNotOwnerNorApproved();
        openEnvelope(tokenId);
        super.safeTransferFrom(from, to, tokenId, data);
    }

    // ✧･ﾟ: *✧･ﾟ:* 7. Other Functions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Function to burn a token.
    /// @dev Overrides the default ERC721 implementation.
    /// @param tokenId ID of the token to burn.
    function burn(uint256 tokenId) public override whenNotPaused {
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
        if (!envelopeOpened.get(tokenId)) {
            envelopeOpened.set(tokenId);
        }
    }

    // ✧･ﾟ: *✧･ﾟ:* 8. Mandatory Overrides ✧･ﾟ: *✧･ﾟ:*
    /// @notice Internal function to update balances and other data.
    /// @dev Overrides multiple inherited functions.
    /// @param to Address receiving the token.
    /// @param tokenId ID of the token being transferred.
    /// @param auth Address authorized for the transfer.
    /// @return Address authorized for the transfer.
    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    /// @notice Function to get the token URI.
    /// @dev Overrides the default ERC721 implementation.
    /// @param tokenId ID of the token.
    /// @return Token URI string.
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (ERC721.ownerOf(tokenId) == address(0)) revert NonexistentToken();
        return
            string.concat(
                baseURI,
                envelopeOpened.get(tokenId) ? "open_" : "closed_",
                Strings.toString(tokenId),
                ".json"
            );
    }

    /// @notice Internal function to increase balance.
    /// @dev Overrides multiple inherited functions.
    /// @param account Address whose balance is to be increased.
    /// @param value Value by which the balance is to be increased.
    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    /// @notice Function to check if the contract supports a given interface.
    /// @dev Overrides multiple inherited functions.
    /// @param interfaceId Interface identifier.
    /// @return Boolean indicating if the interface is supported.
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

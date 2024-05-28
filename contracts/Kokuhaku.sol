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

/**
 * @title Kokuhaku
 * @dev Implementation of the Kokuhaku ERC721 NFT contract with additional features such as pausing, burning, royalty settings, and whitelist functionality.
 */
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

    uint96 public constant maxSupply = 10000;
    string public baseURI;
    string public contractURI;
    uint256 private _nextTokenId;
    BitMaps.BitMap internal envelopeOpened;
    mapping(address => bool) public whiteList;

    /**
     * @dev Initializes the contract by setting the initial owner, royalty fee, base URI, and contract URI.
     * @param initialOwner The address of the initial owner.
     * @param feeNumerator The numerator for the royalty fee.
     * @param initBaseURI The initial base URI for token metadata.
     * @param contractURI_ The URI for the contract metadata.
     */
    constructor(
        address initialOwner,
        uint96 feeNumerator,
        string memory initBaseURI,
        string memory contractURI_
    ) payable ERC721("Kokuhaku", "KOKU") Ownable(initialOwner) {
        if (initialOwner == address(0)) {
            revert ZeroAddressDisallowed();
        }

        require(feeNumerator <= _feeDenominator(), "Invalid fee numerator");

        if (bytes(initBaseURI).length == 0) {
            revert EmptyUriDisallowed();
        }

        if (bytes(contractURI_).length == 0) {
            revert EmptyUriDisallowed();
        }

        baseURI = initBaseURI;
        contractURI = contractURI_;

        _setDefaultRoyalty(initialOwner, feeNumerator);

        unchecked {
            _nextTokenId++;
        }
    }

    /**
    * @notice Pauses all token transfers.
    * @dev Only callable by the owner.
    */
    function pause() external onlyOwner {
        if (paused()) {
            revert AlreadyPaused();
        }
        _pause();
    }

    /**
    * @notice Unpauses all token transfers.
    * @dev Only callable by the owner.
    */
    function unpause() external onlyOwner {
        if (!paused()) {
            revert NotPaused();
        }
        _unpause();
    }

    /**
    * @notice Sets the contract URI.
    * @dev Only callable by the owner.
    * @param contractURI_ The new contract URI.
    */
    function setContractURI(string calldata contractURI_) external onlyOwner {
        if (bytes(contractURI_).length == 0) {
            revert InvalidContractURI();
        }
        contractURI = contractURI_;
    }

    /**
    * @notice Resets the royalty settings.
    * @dev Only callable by the owner.
    * @param receiver The address of the royalty receiver.
    * @param feeNumerator The numerator for the royalty fee.
    */
    function resetRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        if (receiver == address(0)) {
            revert InvalidReceiverAddress();
        }
        if (feeNumerator == 0) {
            revert InvalidFeeNumerator();
        }
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
    * @notice Withdraws the entire balance of the contract to a specified address.
    * @dev Only callable by the owner.
    * @param addr The address to send the balance to.
    */
    function withdraw(address addr) external onlyOwner {
        if (addr == address(0)) {
            revert InvalidAddress();
        }
        bytes4 errorSelector = IKokuhaku.TransferFailed.selector;
        assembly {
            let success := call(gas(), addr, selfbalance(), 0, 0, 0, 0)
            if iszero(success) {
                let ptr := mload(0x40)
                mstore(ptr, errorSelector)
                revert(ptr, 0x4)
            }
        }
    }

    /**
    * @notice Adds a list of addresses to the whitelist.
    * @dev Only callable by the owner.
    * @param addresses The list of addresses to add to the whitelist.
    */
    function setWhiteList(address[] calldata addresses) external onlyOwner {
        if (addresses.length == 0) {
            revert NoAddressesProvided();
        }
        uint256 length = addresses.length;
        for (uint256 i; i < length; i++) {
            if (addresses[i] == address(0)) {
                revert InvalidAddressInList();
            }
            whiteList[addresses[i]] = true;
        }
    }

    /**
    * @notice Sets the base URI for token metadata.
    * @dev Only callable by the owner.
    * @param newBaseURI The new base URI.
    */
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        if (bytes(newBaseURI).length == 0) {
            revert InvalidBaseURI();
        }
        baseURI = newBaseURI;
    }

    /**
     * @notice Mints a token if the caller is on the whitelist.
     * @dev Only callable when not paused.
     * Emits a {FreeMintUsed} event.
     */
    function privateMint() external whenNotPaused {
        if (!whiteList[msg.sender]) revert NotOnWhiteList();

        if (totalSupply() == maxSupply) revert MintingExceedsMaxSupply();

        delete whiteList[msg.sender];

        emit FreeMintUsed(msg.sender);

        _safeMint(msg.sender, _nextTokenId++);
    }

    /**
     * @notice Mints a token to the caller.
     * @dev Only callable when not paused. Requires a payment of 1 ether.
     */
    function publicMint() external payable whenNotPaused {
        if (msg.value != 1 ether) 
            revert NotEnoughFunds();

        if (totalSupply() == maxSupply) 
            revert MintingExceedsMaxSupply();

        _safeMint(msg.sender, _nextTokenId++);
    }

    /**
     * @notice Mints multiple tokens to the caller.
     * @dev Only callable when not paused. Requires a payment of 1 ether per token.
     * @param amount The number of tokens to mint.
     */
    function batchMint(uint256 amount) external payable whenNotPaused {
        if (amount == 0) revert CannotMintZeroTokens();

        if (amount > 10) revert ExceedsBatchLimit();

        unchecked {
            /// @dev the amount is enforced <= 10, so should never overflow
            if (totalSupply() + amount > maxSupply)
                revert MintingExceedsMaxSupply();

            if (msg.value != 1 ether * amount) 
                revert NotEnoughFunds();

            uint256 tokenId = _nextTokenId;

            for (uint256 i; i < amount; i++) {
                _safeMint(msg.sender, tokenId);
                tokenId++;
            }

            _nextTokenId = tokenId;
        }
    }

    /**
     * @notice Mints tokens to a list of recipients.
     * @dev Only callable by the owner.
     * @param recipients The list of addresses to receive tokens.
     */
    function airdropMint(address[] calldata recipients) external onlyOwner {
        uint256 recipientsLength = recipients.length;
        if (totalSupply() + recipientsLength > maxSupply)
            revert MintingExceedsMaxSupply();

        uint256 tokenId = _nextTokenId;

        for (uint256 i; i < recipientsLength; i++) {
            _safeMint(recipients[i], tokenId);
            tokenId++;
        }

        _nextTokenId = tokenId;
    }

    /**
     * @notice Transfers a token from one address to another.
     * @dev Overrides the ERC721 implementation to include envelope opening logic.
     * @param from The address to transfer the token from.
     * @param to The address to transfer the token to.
     * @param tokenId The ID of the token to transfer.
     */
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

    /**
     * @notice Safely transfers a token from one address to another.
     * @dev Overrides the ERC721 implementation to include envelope opening logic.
     * @param from The address to transfer the token from.
     * @param to The address to transfer the token to.
     * @param tokenId The ID of the token to transfer.
     * @param data Additional data with no specified format.
     */
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

    /**
     * @notice Burns a token.
     * @dev Only callable when not paused.
     * @param tokenId The ID of the token to burn.
     */
    function burn(uint256 tokenId) public override whenNotPaused {
        super._burn(tokenId);
    }

    /**
     * @dev Returns the base URI for token metadata.
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Opens the envelope associated with a token.
     * @param tokenId The ID of the token.
     */
    function openEnvelope(uint256 tokenId) private {
        if (!envelopeOpened.get(tokenId)) {
            envelopeOpened.set(tokenId);
        }
    }

    /**
     * @dev Updates the ownership and state of a token.
     * @param to The address to transfer the token to.
     * @param tokenId The ID of the token to transfer.
     * @param auth The address authorized to transfer the token.
     * @return The address of the new owner.
     */
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

    /**
     * @notice Returns the URI for a token's metadata.
     * @param tokenId The ID of the token.
     * @return The URI for the token's metadata.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (ERC721.ownerOf(tokenId) == address(0)) revert NonexistentToken();
        return
            string.concat(
                baseURI,
                envelopeOpened.get(tokenId) ? "open/" : "closed/",
                Strings.toString(tokenId),
                ".json"
            );
    }

    /**
     * @dev Increases the balance of an account.
     * @param account The account to increase the balance of.
     * @param value The amount to increase the balance by.
     */
    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    /**
     * @notice Checks if the contract supports a specific interface.
     * @param interfaceId The interface identifier.
     * @return True if the contract supports the interface, false otherwise.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Kokuhaku NFT Interface
/// @notice This Interface defined an ERC721 NFT with minting, burning, pausing, and royalty functionalities.
interface IKokuhaku {
    // ✧･ﾟ: *✧･ﾟ:* 1. Custom Error Definitions ✧･ﾟ: *✧･ﾟ:*
    error NotOnWhiteList();
    error IncorrectFundsSent();
    error CannotMintZeroTokens();
    error MintingExceedsMaxSupply();
    error NoTokensAvailable();
    error TransferFailed();
    error CallerNotOwnerNorApproved();
    error NonexistentToken();
    error ExceedsBatchLimit();
    error ZeroAddressDisallowed();
    error EmptyUriDisallowed();
    error AlreadyPaused();
    error NotPaused();
    error InvalidContractURI();
    error InvalidReceiverAddress();
    error InvalidFeeNumerator();
    error InvalidAddress();
    error NoAddressesProvided();
    error InvalidAddressInList();
    error InvalidBaseURI();
    error InvalidFeeDenominator();

    // ✧･ﾟ: *✧･ﾟ:* 2. Event Definitions ✧･ﾟ: *✧･ﾟ:*
    /// @notice Event emitted when a free mint is used.
    /// @param user Address of the user who used the free mint.
    event FreeMintUsed(address indexed user);
}

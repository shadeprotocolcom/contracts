// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Types
/// @notice Shared data structures for the Shade Protocol privacy system.

/// @notice The type of token being shielded. Currently only ERC20 (including wrapped native).
enum TokenType {
    ERC20
}

/// @notice Whether an unshield is requested and its flavour.
enum UnshieldType {
    NONE,
    NORMAL
}

/// @notice Identifies a specific token (address + optional sub-ID for ERC-1155 style).
struct TokenData {
    TokenType tokenType;
    address tokenAddress;
    uint256 tokenSubID;
}

/// @notice Plaintext note fields that, once hashed, become a Merkle leaf.
struct CommitmentPreimage {
    bytes32 npk; // note public key (derived from recipient spending key)
    TokenData token;
    uint120 value;
}

/// @notice Encrypted data attached to a shield operation so the recipient can decrypt.
struct ShieldCiphertext {
    bytes32[3] encryptedBundle;
    bytes32 shieldKey;
}

/// @notice Encrypted data attached to each new commitment in a transact call.
struct CommitmentCiphertext {
    bytes32[4] ciphertext;
    bytes32 blindedSenderViewingKey;
    bytes32 blindedReceiverViewingKey;
    bytes annotationData;
    bytes memo;
}

/// @notice Circuit-bound public parameters that are part of the proof's public inputs.
struct BoundParams {
    uint16 treeNumber;
    UnshieldType unshield;
    uint64 chainID;
    CommitmentCiphertext[] commitmentCiphertext;
}

/// @notice A Groth16 proof (3 elliptic-curve points on BN254).
struct SnarkProof {
    uint256[2] a;
    uint256[2][2] b;
    uint256[2] c;
}

/// @notice A single private transaction submitted to the pool.
struct Transaction {
    SnarkProof proof;
    bytes32 merkleRoot;
    bytes32[] nullifiers;
    bytes32[] commitments;
    BoundParams boundParams;
    CommitmentPreimage unshieldPreimage;
}

/// @notice A request to shield (deposit) tokens into the private pool.
struct ShieldRequest {
    CommitmentPreimage preimage;
    ShieldCiphertext ciphertext;
}

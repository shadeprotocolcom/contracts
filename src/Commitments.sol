// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoseidonT3} from "./PoseidonT3.sol";

/// @title Commitments
/// @notice Binary Poseidon Merkle tree (depth 16) with incremental batch insertion.
/// @dev Clean-room implementation inspired by MACI-style incremental Merkle trees.
///      Each leaf is a Poseidon commitment hash. Internal nodes use PoseidonT3
///      (hash of 2 inputs). Supports multiple sequential trees: when a tree fills
///      up (2^16 = 65 536 leaves) a new tree is started automatically.
abstract contract Commitments {
    // -----------------------------------------------------------------------
    //  Constants
    // -----------------------------------------------------------------------

    /// @notice BN254 scalar field order (also known as the snark scalar field).
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    /// @notice Depth of the binary Merkle tree.
    uint256 internal constant TREE_DEPTH = 16;

    /// @notice Maximum number of leaves per tree: 2^16.
    uint256 internal constant MAX_LEAVES = 65536;

    // -----------------------------------------------------------------------
    //  State
    // -----------------------------------------------------------------------

    /// @notice Current tree number (starts at 0, incremented when a tree fills up).
    uint256 public treeNumber;

    /// @notice Index of the next empty leaf in the current tree.
    uint256 public nextLeafIndex;

    /// @notice Current Merkle root of the active tree.
    bytes32 public merkleRoot;

    /// @notice Precomputed zero values for each level of the tree.
    ///         zeros[0] = leaf-level zero, zeros[TREE_DEPTH-1] = root-level zero.
    bytes32[TREE_DEPTH] public zeros;

    /// @notice Filled subtree hashes used for incremental insertion.
    bytes32[TREE_DEPTH] private filledSubTrees;

    /// @notice Tracks which roots have ever been valid.  treeNumber => root => bool.
    mapping(uint256 => mapping(bytes32 => bool)) public rootHistory;

    /// @notice Tracks spent nullifiers.  treeNumber => nullifier => bool.
    mapping(uint256 => mapping(bytes32 => bool)) public nullifiers;

    // -----------------------------------------------------------------------
    //  Constructor helper (called by derived contract)
    // -----------------------------------------------------------------------

    /// @dev Initialise zero values and the empty-tree root.
    function _initMerkleTree() internal {
        // Level 0 zero value derived deterministically.
        bytes32 zeroValue = bytes32(uint256(keccak256("Shade")) % SNARK_SCALAR_FIELD);
        zeros[0] = zeroValue;
        filledSubTrees[0] = zeroValue;

        // Compute zeros for each subsequent level: zeros[i] = H(zeros[i-1], zeros[i-1])
        for (uint256 i = 1; i < TREE_DEPTH; i++) {
            zeroValue = _hashLeftRight(zeroValue, zeroValue);
            zeros[i] = zeroValue;
            filledSubTrees[i] = zeroValue;
        }

        // The empty-tree root is valid.
        merkleRoot = _hashLeftRight(zeros[TREE_DEPTH - 1], zeros[TREE_DEPTH - 1]);
        rootHistory[0][merkleRoot] = true;
    }

    // -----------------------------------------------------------------------
    //  Internal insertion
    // -----------------------------------------------------------------------

    /// @notice Insert an array of leaf hashes into the current Merkle tree.
    /// @dev If the current tree overflows, a new tree is started. All leaves in
    ///      a single call must fit within one tree (revert otherwise).
    /// @param leafHashes Array of commitment hashes to insert.
    /// @return startPosition The index of the first inserted leaf.
    function _insertLeaves(bytes32[] memory leafHashes) internal returns (uint256 startPosition) {
        uint256 leavesCount = leafHashes.length;
        require(leavesCount > 0, "Commitments: empty leaves");

        uint256 currentIndex = nextLeafIndex;

        // If the current tree is full, rotate to a new tree.
        if (currentIndex >= MAX_LEAVES) {
            _startNewTree();
            currentIndex = 0;
        }

        require(currentIndex + leavesCount <= MAX_LEAVES, "Commitments: batch exceeds tree capacity");

        startPosition = currentIndex;

        for (uint256 i = 0; i < leavesCount; i++) {
            bytes32 leaf = leafHashes[i];
            require(uint256(leaf) < SNARK_SCALAR_FIELD, "Commitments: leaf >= SNARK_SCALAR_FIELD");

            uint256 leafIndex = currentIndex + i;
            bytes32 currentLevelHash = leaf;

            // Walk up the tree, hashing with either the filled subtree or the zero value.
            for (uint256 level = 0; level < TREE_DEPTH; level++) {
                if ((leafIndex >> level) & 1 == 0) {
                    // This node is a left child. The right sibling is the zero (or a
                    // previously-filled subtree that will be overwritten on the next pass).
                    // Store current hash as the filled subtree for this level.
                    filledSubTrees[level] = currentLevelHash;
                    currentLevelHash = _hashLeftRight(currentLevelHash, zeros[level]);
                } else {
                    // This node is a right child. The left sibling is the stored filledSubTree.
                    currentLevelHash = _hashLeftRight(filledSubTrees[level], currentLevelHash);
                }
            }

            merkleRoot = currentLevelHash;
        }

        nextLeafIndex = currentIndex + leavesCount;
        rootHistory[treeNumber][merkleRoot] = true;
    }

    // -----------------------------------------------------------------------
    //  Private helpers
    // -----------------------------------------------------------------------

    /// @dev Start a fresh tree after the current one is full.
    function _startNewTree() private {
        treeNumber++;
        nextLeafIndex = 0;

        // Reset filledSubTrees to zeros.
        for (uint256 i = 0; i < TREE_DEPTH; i++) {
            filledSubTrees[i] = zeros[i];
        }

        // Compute and store empty-tree root.
        merkleRoot = _hashLeftRight(zeros[TREE_DEPTH - 1], zeros[TREE_DEPTH - 1]);
        rootHistory[treeNumber][merkleRoot] = true;
    }

    /// @notice Poseidon hash of two field elements (binary Merkle node).
    /// @param left  Left child hash.
    /// @param right Right child hash.
    /// @return The Poseidon hash of (left, right).
    function _hashLeftRight(bytes32 left, bytes32 right) internal pure returns (bytes32) {
        return PoseidonT3.poseidon([left, right]);
    }
}

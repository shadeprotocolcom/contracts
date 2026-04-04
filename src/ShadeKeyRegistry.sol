// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ShadeKeyRegistry
 * @notice On-chain registry for Shade Protocol public keys.
 *
 * Users register their viewing public key (BabyJubjub point) and master
 * public key so that senders can look them up by Ethereum address. This
 * removes the dependency on a centralized indexer for key distribution.
 *
 * Keys are authenticated by `msg.sender` — only the owner can set their
 * own keys. Overwrites are allowed (e.g. after wallet recovery).
 */
contract ShadeKeyRegistry {
    struct PublicKeys {
        bytes32 viewingPubKeyX; // BabyJubjub x-coordinate
        bytes32 viewingPubKeyY; // BabyJubjub y-coordinate
        bytes32 masterPublicKey; // Poseidon(spendPubKey.x, spendPubKey.y, nullifyingKey)
    }

    mapping(address => PublicKeys) private _keys;

    event KeysRegistered(
        address indexed account,
        bytes32 viewingPubKeyX,
        bytes32 viewingPubKeyY,
        bytes32 masterPublicKey
    );

    /**
     * @notice Register or update your Shade public keys.
     * @param viewingPubKeyX  BabyJubjub viewing public key x-coordinate.
     * @param viewingPubKeyY  BabyJubjub viewing public key y-coordinate.
     * @param masterPublicKey Master public key (single field element).
     */
    function registerKeys(
        bytes32 viewingPubKeyX,
        bytes32 viewingPubKeyY,
        bytes32 masterPublicKey
    ) external {
        require(masterPublicKey != bytes32(0), "ShadeKeyRegistry: masterPublicKey cannot be zero");

        _keys[msg.sender] = PublicKeys(viewingPubKeyX, viewingPubKeyY, masterPublicKey);
        emit KeysRegistered(msg.sender, viewingPubKeyX, viewingPubKeyY, masterPublicKey);
    }

    /**
     * @notice Look up a user's registered public keys.
     * @param account Ethereum address to look up.
     * @return viewingPubKeyX  BabyJubjub x-coordinate.
     * @return viewingPubKeyY  BabyJubjub y-coordinate.
     * @return masterPublicKey Master public key.
     */
    function getKeys(address account)
        external
        view
        returns (bytes32 viewingPubKeyX, bytes32 viewingPubKeyY, bytes32 masterPublicKey)
    {
        PublicKeys storage k = _keys[account];
        return (k.viewingPubKeyX, k.viewingPubKeyY, k.masterPublicKey);
    }

    /**
     * @notice Check whether an address has registered keys.
     * @param account Ethereum address to check.
     * @return True if the account has a non-zero masterPublicKey.
     */
    function isRegistered(address account) external view returns (bool) {
        return _keys[account].masterPublicKey != bytes32(0);
    }
}

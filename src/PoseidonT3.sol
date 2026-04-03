// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PoseidonT3
/// @notice Poseidon hash function for 2 inputs (t=3).
/// @dev In production, this library is replaced at deploy time by linking against
///      the real Poseidon bytecode from circomlibjs / zk-kit via Foundry's
///      `--libraries` flag. The implementation below is a keccak256-based
///      placeholder that keeps the same function signature so the rest of the
///      codebase compiles and tests can run without the real Poseidon circuit.
///
///      To deploy with the real Poseidon:
///        forge script ... --libraries src/PoseidonT3.sol:PoseidonT3:<DEPLOYED_ADDR>
library PoseidonT3 {
    uint256 private constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    function poseidon(bytes32[2] memory inputs) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encodePacked(inputs[0], inputs[1]))) % SNARK_SCALAR_FIELD);
    }
}

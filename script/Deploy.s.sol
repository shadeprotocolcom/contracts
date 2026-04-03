// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ShadePool} from "../src/ShadePool.sol";

/// @title Deploy
/// @notice Foundry deployment script for the Shade Protocol contracts on Citrea.
/// @dev Usage:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url citrea_mainnet \
///     --broadcast \
///     --verify \
///     -vvvv
///
///   Required environment variables:
///     DEPLOYER_PRIVATE_KEY - Private key for the deployer account.
///     WCBTC_ADDRESS        - Address of the WcBTC (WETH9-style) contract on Citrea.
///     VERIFIER_ADDRESS     - Address of the pre-deployed Groth16 verifier.
///     POSEIDON_T3_ADDRESS  - Address of the pre-deployed PoseidonT3 library.
///     POSEIDON_T4_ADDRESS  - Address of the pre-deployed PoseidonT4 library.
///
///   Poseidon libraries must be deployed beforehand from circomlibjs / zk-kit
///   bytecode, then their addresses passed via environment variables so Foundry
///   can link them at deploy time.
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address wcBTC = vm.envAddress("WCBTC_ADDRESS");
        address verifierAddr = vm.envAddress("VERIFIER_ADDRESS");
        address poseidonT3 = vm.envAddress("POSEIDON_T3_ADDRESS");
        address poseidonT4 = vm.envAddress("POSEIDON_T4_ADDRESS");

        console2.log("Deployer:", vm.addr(deployerPrivateKey));
        console2.log("WcBTC:", wcBTC);
        console2.log("Verifier:", verifierAddr);
        console2.log("PoseidonT3:", poseidonT3);
        console2.log("PoseidonT4:", poseidonT4);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy ShadePool with library linking handled by Foundry's --libraries flag.
        // Command line must include:
        //   --libraries src/PoseidonT3.sol:PoseidonT3:<POSEIDON_T3_ADDRESS>
        //   --libraries src/PoseidonT4.sol:PoseidonT4:<POSEIDON_T4_ADDRESS>
        ShadePool pool = new ShadePool(wcBTC, verifierAddr);

        console2.log("ShadePool deployed at:", address(pool));
        console2.log("Tree number:", pool.treeNumber());
        console2.log("Chain ID constant:", pool.CHAIN_ID());

        vm.stopBroadcast();
    }
}

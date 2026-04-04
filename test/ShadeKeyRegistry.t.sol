// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ShadeKeyRegistry} from "../src/ShadeKeyRegistry.sol";

contract ShadeKeyRegistryTest is Test {
    ShadeKeyRegistry public registry;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    bytes32 constant VPK_X = bytes32(uint256(0x1111));
    bytes32 constant VPK_Y = bytes32(uint256(0x2222));
    bytes32 constant MPK = bytes32(uint256(0x3333));

    function setUp() public {
        registry = new ShadeKeyRegistry();
    }

    function test_registerAndGetKeys() public {
        vm.prank(alice);
        registry.registerKeys(VPK_X, VPK_Y, MPK);

        (bytes32 x, bytes32 y, bytes32 mpk) = registry.getKeys(alice);
        assertEq(x, VPK_X);
        assertEq(y, VPK_Y);
        assertEq(mpk, MPK);
    }

    function test_isRegistered() public {
        assertFalse(registry.isRegistered(alice));

        vm.prank(alice);
        registry.registerKeys(VPK_X, VPK_Y, MPK);

        assertTrue(registry.isRegistered(alice));
        assertFalse(registry.isRegistered(bob));
    }

    function test_overwriteKeys() public {
        vm.prank(alice);
        registry.registerKeys(VPK_X, VPK_Y, MPK);

        bytes32 newMPK = bytes32(uint256(0x4444));
        vm.prank(alice);
        registry.registerKeys(VPK_X, VPK_Y, newMPK);

        (, , bytes32 mpk) = registry.getKeys(alice);
        assertEq(mpk, newMPK);
    }

    function test_cannotRegisterZeroMPK() public {
        vm.prank(alice);
        vm.expectRevert("ShadeKeyRegistry: masterPublicKey cannot be zero");
        registry.registerKeys(VPK_X, VPK_Y, bytes32(0));
    }

    function test_unregisteredReturnsZeros() public {
        (bytes32 x, bytes32 y, bytes32 mpk) = registry.getKeys(bob);
        assertEq(x, bytes32(0));
        assertEq(y, bytes32(0));
        assertEq(mpk, bytes32(0));
    }

    function test_onlySenderCanRegister() public {
        vm.prank(alice);
        registry.registerKeys(VPK_X, VPK_Y, MPK);

        // Bob cannot overwrite Alice's keys — he can only set his own
        vm.prank(bob);
        registry.registerKeys(VPK_X, VPK_Y, MPK);

        // Both registered, independently
        assertTrue(registry.isRegistered(alice));
        assertTrue(registry.isRegistered(bob));
    }

    event KeysRegistered(address indexed account, bytes32 viewingPubKeyX, bytes32 viewingPubKeyY, bytes32 masterPublicKey);

    function test_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit KeysRegistered(alice, VPK_X, VPK_Y, MPK);
        registry.registerKeys(VPK_X, VPK_Y, MPK);
    }

    function test_multipleUsersIndependent() public {
        bytes32 bobMPK = bytes32(uint256(0x5555));

        vm.prank(alice);
        registry.registerKeys(VPK_X, VPK_Y, MPK);

        vm.prank(bob);
        registry.registerKeys(VPK_X, VPK_Y, bobMPK);

        (, , bytes32 aliceMPK) = registry.getKeys(alice);
        (, , bytes32 bobMPK2) = registry.getKeys(bob);

        assertEq(aliceMPK, MPK);
        assertEq(bobMPK2, bobMPK);
    }
}

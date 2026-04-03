// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ShadePool} from "../src/ShadePool.sol";
import {IVerifier} from "../src/IVerifier.sol";
import {
    ShieldRequest,
    CommitmentPreimage,
    ShieldCiphertext,
    TokenData,
    TokenType,
    Transaction,
    SnarkProof,
    BoundParams,
    CommitmentCiphertext,
    UnshieldType
} from "../src/Types.sol";

// ---------------------------------------------------------------------------
//  Mock Verifier -- always returns true (for unit testing only)
// ---------------------------------------------------------------------------
contract MockVerifier is IVerifier {
    bool public shouldReturn;

    constructor(bool _shouldReturn) {
        shouldReturn = _shouldReturn;
    }

    function setShouldReturn(bool _val) external {
        shouldReturn = _val;
    }

    function verifyProof(
        uint[2] calldata,
        uint[2][2] calldata,
        uint[2] calldata,
        uint[6] calldata
    ) external view returns (bool) {
        return shouldReturn;
    }
}

// ---------------------------------------------------------------------------
//  Mock WcBTC -- minimal WETH9 behaviour for tests
// ---------------------------------------------------------------------------
contract MockWcBTC {
    string public name = "Wrapped cBTC";
    string public symbol = "WcBTC";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad, "MockWcBTC: insufficient balance");
        balanceOf[msg.sender] -= wad;
        (bool sent,) = msg.sender.call{value: wad}("");
        require(sent, "MockWcBTC: transfer failed");
        emit Withdrawal(msg.sender, wad);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "MockWcBTC: allowance exceeded");
            allowance[from][msg.sender] = allowed - amount;
        }
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "MockWcBTC: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// ---------------------------------------------------------------------------
//  Test contract
// ---------------------------------------------------------------------------
contract ShadePoolTest is Test {
    ShadePool public pool;
    MockVerifier public mockVerifier;
    MockWcBTC public mockWcBTC;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        mockWcBTC = new MockWcBTC();
        mockVerifier = new MockVerifier(true);

        // Poseidon libraries use internal functions (inlined by the compiler),
        // so no external linking is needed for tests.
        pool = new ShadePool(address(mockWcBTC), address(mockVerifier));

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // -----------------------------------------------------------------------
    //  Helper: build a simple ShieldRequest
    // -----------------------------------------------------------------------

    function _makeShieldRequest(uint120 value) internal view returns (ShieldRequest memory) {
        TokenData memory token = TokenData({
            tokenType: TokenType.ERC20,
            tokenAddress: address(mockWcBTC),
            tokenSubID: 0
        });

        CommitmentPreimage memory preimage = CommitmentPreimage({
            npk: bytes32(uint256(0xDEAD)),
            token: token,
            value: value
        });

        ShieldCiphertext memory cipher = ShieldCiphertext({
            encryptedBundle: [bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3))],
            shieldKey: bytes32(uint256(0xBEEF))
        });

        return ShieldRequest({preimage: preimage, ciphertext: cipher});
    }

    // -----------------------------------------------------------------------
    //  Test: shield with native cBTC
    // -----------------------------------------------------------------------

    function test_shieldNativeCBTC() public {
        uint120 amount = 1 ether;
        ShieldRequest[] memory requests = new ShieldRequest[](1);
        requests[0] = _makeShieldRequest(amount);

        vm.prank(alice);
        pool.shield{value: amount}(requests);

        // Verify the Merkle tree advanced.
        assertEq(pool.nextLeafIndex(), 1, "nextLeafIndex should be 1 after one shield");

        // Verify WcBTC was wrapped (pool holds WcBTC).
        assertEq(mockWcBTC.balanceOf(address(pool)), amount, "pool should hold WcBTC");
    }

    // -----------------------------------------------------------------------
    //  Test: shield with pre-approved WcBTC
    // -----------------------------------------------------------------------

    function test_shieldPreApprovedWcBTC() public {
        uint120 amount = 2 ether;

        // Alice wraps some cBTC herself, then approves the pool.
        vm.startPrank(alice);
        mockWcBTC.deposit{value: amount}();
        mockWcBTC.approve(address(pool), amount);

        ShieldRequest[] memory requests = new ShieldRequest[](1);
        requests[0] = _makeShieldRequest(amount);

        pool.shield(requests); // no msg.value
        vm.stopPrank();

        assertEq(pool.nextLeafIndex(), 1);
        assertEq(mockWcBTC.balanceOf(address(pool)), amount);
    }

    // -----------------------------------------------------------------------
    //  Test: shield rejects zero value
    // -----------------------------------------------------------------------

    function test_shieldRejectsZeroValue() public {
        ShieldRequest[] memory requests = new ShieldRequest[](1);
        requests[0] = _makeShieldRequest(0);

        vm.prank(alice);
        vm.expectRevert("TokenGuard: zero value");
        pool.shield(requests);
    }

    // -----------------------------------------------------------------------
    //  Test: shield rejects excess native value
    // -----------------------------------------------------------------------

    function test_shieldRejectsExcessNative() public {
        uint120 amount = 1 ether;
        ShieldRequest[] memory requests = new ShieldRequest[](1);
        requests[0] = _makeShieldRequest(amount);

        vm.prank(alice);
        vm.expectRevert("ShadePool: excess native value");
        pool.shield{value: 2 ether}(requests);
    }

    // -----------------------------------------------------------------------
    //  Test: double-spend prevention (nullifier reuse)
    // -----------------------------------------------------------------------

    function test_doubleSpendPrevention() public {
        // First, shield some value so the Merkle tree has a valid root.
        uint120 amount = 1 ether;
        ShieldRequest[] memory requests = new ShieldRequest[](1);
        requests[0] = _makeShieldRequest(amount);
        vm.prank(alice);
        pool.shield{value: amount}(requests);

        // Build a transaction with a nullifier.
        bytes32 testNullifier = bytes32(uint256(0x1234));
        bytes32 currentRoot = pool.merkleRoot();

        Transaction[] memory txns = new Transaction[](1);
        txns[0] = _makeTransaction(currentRoot, testNullifier, pool.treeNumber());

        // First transact should succeed.
        pool.transact(txns);

        // Second transact with the same nullifier should revert.
        txns[0] = _makeTransaction(currentRoot, testNullifier, pool.treeNumber());
        vm.expectRevert("ShadePool: nullifier already spent");
        pool.transact(txns);
    }

    // -----------------------------------------------------------------------
    //  Test: invalid Merkle root rejection
    // -----------------------------------------------------------------------

    function test_invalidMerkleRootRejection() public {
        bytes32 fakeRoot = bytes32(uint256(0x9999));
        bytes32 testNullifier = bytes32(uint256(0x5678));

        Transaction[] memory txns = new Transaction[](1);
        txns[0] = _makeTransaction(fakeRoot, testNullifier, 0);

        vm.expectRevert("ShadePool: unknown Merkle root");
        pool.transact(txns);
    }

    // -----------------------------------------------------------------------
    //  Test: wrong chain ID rejection
    // -----------------------------------------------------------------------

    function test_wrongChainIdRejection() public {
        // Shield first to get a valid root.
        uint120 amount = 1 ether;
        ShieldRequest[] memory requests = new ShieldRequest[](1);
        requests[0] = _makeShieldRequest(amount);
        vm.prank(alice);
        pool.shield{value: amount}(requests);

        bytes32 currentRoot = pool.merkleRoot();
        bytes32 testNullifier = bytes32(uint256(0xABCD));

        Transaction[] memory txns = new Transaction[](1);
        txns[0] = _makeTransactionWithChainId(currentRoot, testNullifier, pool.treeNumber(), 1);

        vm.expectRevert("ShadePool: wrong chain ID");
        pool.transact(txns);
    }

    // -----------------------------------------------------------------------
    //  Test: invalid proof rejection
    // -----------------------------------------------------------------------

    function test_invalidProofRejection() public {
        // Shield first.
        uint120 amount = 1 ether;
        ShieldRequest[] memory requests = new ShieldRequest[](1);
        requests[0] = _makeShieldRequest(amount);
        vm.prank(alice);
        pool.shield{value: amount}(requests);

        // Set verifier to reject.
        mockVerifier.setShouldReturn(false);

        bytes32 currentRoot = pool.merkleRoot();
        bytes32 testNullifier = bytes32(uint256(0xEEEE));

        Transaction[] memory txns = new Transaction[](1);
        txns[0] = _makeTransaction(currentRoot, testNullifier, pool.treeNumber());

        vm.expectRevert("ShadePool: invalid proof");
        pool.transact(txns);
    }

    // -----------------------------------------------------------------------
    //  Test: multiple shields increment tree correctly
    // -----------------------------------------------------------------------

    function test_multipleShieldsIncrementTree() public {
        uint120 amount = 0.5 ether;

        for (uint256 i = 0; i < 5; i++) {
            ShieldRequest[] memory requests = new ShieldRequest[](1);
            requests[0] = _makeShieldRequest(amount);
            vm.prank(alice);
            pool.shield{value: amount}(requests);
        }

        assertEq(pool.nextLeafIndex(), 5, "nextLeafIndex should be 5 after five shields");
        assertEq(mockWcBTC.balanceOf(address(pool)), 2.5 ether, "pool should hold 2.5 WcBTC");
    }

    // -----------------------------------------------------------------------
    //  Test: batch shield in single call
    // -----------------------------------------------------------------------

    function test_batchShield() public {
        uint120 amountEach = 0.3 ether;
        uint256 count = 3;

        ShieldRequest[] memory requests = new ShieldRequest[](count);
        for (uint256 i = 0; i < count; i++) {
            requests[i] = _makeShieldRequest(amountEach);
        }

        vm.prank(alice);
        pool.shield{value: uint256(amountEach) * count}(requests);

        assertEq(pool.nextLeafIndex(), count, "nextLeafIndex should equal batch count");
    }

    // -----------------------------------------------------------------------
    //  Test helpers
    // -----------------------------------------------------------------------

    function _makeTransaction(
        bytes32 root,
        bytes32 nullifier,
        uint256 tree
    ) internal pure returns (Transaction memory) {
        return _makeTransactionWithChainId(root, nullifier, tree, 4114);
    }

    function _makeTransactionWithChainId(
        bytes32 root,
        bytes32 nullifier,
        uint256 tree,
        uint64 chainId
    ) internal pure returns (Transaction memory) {
        SnarkProof memory proof = SnarkProof({
            a: [uint256(0), uint256(0)],
            b: [[uint256(0), uint256(0)], [uint256(0), uint256(0)]],
            c: [uint256(0), uint256(0)]
        });

        bytes32[] memory nullifiers_ = new bytes32[](2);
        nullifiers_[0] = nullifier;
        nullifiers_[1] = bytes32(uint256(nullifier) + 1);

        // Two output commitments (circuit expects exactly 2).
        bytes32[] memory commitments_ = new bytes32[](2);
        commitments_[0] = bytes32(uint256(0x42));
        commitments_[1] = bytes32(uint256(0x43));

        CommitmentCiphertext[] memory ctArray = new CommitmentCiphertext[](2);
        ctArray[0] = CommitmentCiphertext({
            ciphertext: [bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3)), bytes32(uint256(4))],
            blindedSenderViewingKey: bytes32(uint256(0xA)),
            blindedReceiverViewingKey: bytes32(uint256(0xB)),
            annotationData: "",
            memo: ""
        });
        ctArray[1] = CommitmentCiphertext({
            ciphertext: [bytes32(uint256(5)), bytes32(uint256(6)), bytes32(uint256(7)), bytes32(uint256(8))],
            blindedSenderViewingKey: bytes32(uint256(0xC)),
            blindedReceiverViewingKey: bytes32(uint256(0xD)),
            annotationData: "",
            memo: ""
        });

        BoundParams memory bp = BoundParams({
            treeNumber: uint16(tree),
            unshield: UnshieldType.NONE,
            chainID: chainId,
            commitmentCiphertext: ctArray
        });

        TokenData memory tokenData = TokenData({
            tokenType: TokenType.ERC20,
            tokenAddress: address(0),
            tokenSubID: 0
        });

        CommitmentPreimage memory unshieldPreimage = CommitmentPreimage({
            npk: bytes32(0),
            token: tokenData,
            value: 0
        });

        return Transaction({
            proof: proof,
            merkleRoot: root,
            nullifiers: nullifiers_,
            commitments: commitments_,
            boundParams: bp,
            unshieldPreimage: unshieldPreimage
        });
    }
}

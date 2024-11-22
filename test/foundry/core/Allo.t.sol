// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

// Interfaces
import {IAllo} from "../../../contracts/core/interfaces/IAllo.sol";
import {IStrategy} from "../../../contracts/core/interfaces/IStrategy.sol";
// Core contracts
import {Allo} from "../../../contracts/core/Allo.sol";
import {Registry} from "../../../contracts/core/Registry.sol";
// Internal Libraries
import {Errors} from "../../../contracts/core/libraries/Errors.sol";
import {Metadata} from "../../../contracts/core/libraries/Metadata.sol";
import {Native} from "../../../contracts/core/libraries/Native.sol";
// Test libraries
import {AlloSetup} from "../shared/AlloSetup.sol";
import {RegistrySetupFull} from "../shared/RegistrySetup.sol";
import {TestStrategy} from "../../utils/TestStrategy.sol";
import {MockStrategy} from "../../utils/MockStrategy.sol";
import {MockERC20} from "../../utils/MockERC20.sol";
import {GasHelpers} from "../../utils/GasHelpers.sol";

contract ForceSendEther {
    constructor() payable {}
    
    function forceSend(address payable recipient) external {
        selfdestruct(recipient);
    }
    
    receive() external payable {}
}

contract MockFeeToken is MockERC20 {
    uint256 constant FEE_DENOMINATOR = 1000;
    uint256 constant FEE_RATE = 10; // 1% fee

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        uint256 fee = (amount * FEE_RATE) / FEE_DENOMINATOR;
        uint256 actualAmount = amount - fee;
        super.transfer(to, actualAmount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        uint256 fee = (amount * FEE_RATE) / FEE_DENOMINATOR;
        uint256 actualAmount = amount - fee;
        super.transferFrom(from, to, actualAmount);
        return true;
    }
}

contract MockReentrantStrategy {
    Allo public immutable allo;
    bool public attacking;

    constructor(address _allo) {
        allo = Allo(_allo);
    }

    // Function to receive ETH
    receive() external payable {
        if (attacking) {
            attacking = false;
            allo.fundPool{value: msg.value}(1, msg.value);
        }
    }

    function attack(uint256 poolId) external payable {
        attacking = true;
        allo.fundPool{value: msg.value}(poolId, msg.value);
    }
}

contract MaliciousToken is MockERC20 {
    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }
    
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }
}

contract AlloTest is Test, AlloSetup, RegistrySetupFull, Native, Errors, GasHelpers {
    event PoolCreated(
        uint256 indexed poolId,
        bytes32 indexed profileId,
        IStrategy strategy,
        address token,
        uint256 amount,
        Metadata metadata
    );
    event PoolMetadataUpdated(uint256 indexed poolId, Metadata metadata);
    event PoolFunded(uint256 indexed poolId, uint256 amount, uint256 fee);
    event BaseFeePaid(uint256 indexed poolId, uint256 amount);
    event TreasuryUpdated(address treasury);
    event PercentFeeUpdated(uint256 percentFee);
    event BaseFeeUpdated(uint256 baseFee);
    event RegistryUpdated(address registry);
    event StrategyApproved(address strategy);
    event StrategyRemoved(address strategy);

    error AlreadyInitialized();

    address public strategy;
    MockERC20 public token;

    uint256 mintAmount = 1000000 * 10 ** 18;

    Metadata public metadata = Metadata({protocol: 1, pointer: "strategy pointer"});
    string public name;
    uint256 public nonce;

    function setUp() public {
        __RegistrySetupFull();
        __AlloSetup(address(registry()));

        token = new MockERC20();
        token.mint(local(), mintAmount);
        token.mint(allo_owner(), mintAmount);
        token.mint(pool_admin(), mintAmount);
        token.approve(address(allo()), mintAmount);

        vm.prank(pool_admin());
        token.approve(address(allo()), mintAmount);

        strategy = address(new MockStrategy(address(allo())));

        vm.startPrank(allo_owner());
        allo().transferOwnership(local());
        vm.stopPrank();
    }

    function _utilCreatePool(uint256 _amount) internal returns (uint256) {
        vm.prank(pool_admin());
        return allo().createPoolWithCustomStrategy(
            poolProfile_id(), strategy, "0x", address(token), _amount, metadata, pool_managers()
        );
    }

    function test_initialize() public {
        Allo coreContract = new Allo();
        vm.expectEmit(true, false, false, true);

        emit RegistryUpdated(address(registry()));
        emit TreasuryUpdated(address(allo_treasury()));
        emit PercentFeeUpdated(1e16);
        emit BaseFeeUpdated(1e16);

        coreContract.initialize(
            address(allo_owner()), // _owner
            address(registry()), // _registry
            allo_treasury(), // _treasury
            1e16, // _percentFee
            1e15 // _baseFee
        );

        assertEq(address(coreContract.getRegistry()), address(registry()));
        assertEq(coreContract.getTreasury(), allo_treasury());
        assertEq(coreContract.getPercentFee(), 1e16);
        assertEq(coreContract.getBaseFee(), 1e15);
    }

    function testRevert_initialize_ALREADY_INITIALIZED() public {
        vm.expectRevert("Initializable: contract is already initialized");

        allo().initialize(
            address(allo_owner()), // _owner
            address(registry()), // _registry
            allo_treasury(), // _treasury
            1e16, // _percentFee
            1e15 // _baseFee
        );
    }

    function test_createPool() public {
        startMeasuringGas("createPool");
        allo().addToCloneableStrategies(strategy);

        vm.expectEmit(true, true, false, false);
        emit PoolCreated(1, poolProfile_id(), IStrategy(strategy), NATIVE, 0, metadata);

        vm.prank(pool_admin());
        uint256 poolId = allo().createPool(poolProfile_id(), strategy, "0x", NATIVE, 0, metadata, pool_managers());

        IAllo.Pool memory pool = allo().getPool(poolId);
        stopMeasuringGas();

        assertEq(pool.profileId, poolProfile_id());
        assertNotEq(address(pool.strategy), address(strategy));
    }

    function testRevert_createPool_NOT_APPROVED_STRATEGY() public {
        vm.expectRevert(NOT_APPROVED_STRATEGY.selector);
        vm.prank(pool_admin());
        allo().createPool(poolProfile_id(), strategy, "0x", NATIVE, 0, metadata, pool_managers());
    }

    function testRevert_createPoolWithCustomStrategy_ZERO_ADDRESS() public {
        vm.expectRevert(ZERO_ADDRESS.selector);
        vm.prank(pool_admin());
        allo().createPoolWithCustomStrategy(poolProfile_id(), address(0), "0x", NATIVE, 0, metadata, pool_managers());
    }

    function testRevert_createPoolWithCustomStrategy_IS_APPROVED_STRATEGY() public {
        allo().addToCloneableStrategies(strategy);
        vm.expectRevert(IS_APPROVED_STRATEGY.selector);
        vm.prank(pool_admin());
        allo().createPoolWithCustomStrategy(poolProfile_id(), strategy, "0x", NATIVE, 0, metadata, pool_managers());
    }

    function testRevert_createPool_UNAUTHORIZED() public {
        vm.expectRevert(UNAUTHORIZED.selector);
        allo().createPoolWithCustomStrategy(poolProfile_id(), strategy, "0x", NATIVE, 0, metadata, pool_managers());
    }

    function testRevert_createPool_poolId_MISMATCH() public {
        TestStrategy testStrategy = new TestStrategy(makeAddr("allo"), "TestStrategy");
        testStrategy.setPoolId(0);

        vm.expectRevert(MISMATCH.selector);
        vm.prank(pool_admin());
        allo().createPoolWithCustomStrategy(
            poolProfile_id(), address(testStrategy), "0x", NATIVE, 0, metadata, pool_managers()
        );
    }

    function testRevert_createPool_allo_MISMATCH() public {
        TestStrategy testStrategy = new TestStrategy(makeAddr("allo"), "TestStrategy");
        testStrategy.setAllo(address(0));

        vm.expectRevert(MISMATCH.selector);
        vm.prank(pool_admin());
        allo().createPoolWithCustomStrategy(
            poolProfile_id(), address(testStrategy), "0x", NATIVE, 0, metadata, pool_managers()
        );
    }

    function testRevert_createPool_ZERO_ADDRESS() public {
        address[] memory poolManagers = new address[](1);
        poolManagers[0] = address(0);
        vm.expectRevert(ZERO_ADDRESS.selector);
        vm.prank(pool_admin());
        allo().createPoolWithCustomStrategy(poolProfile_id(), strategy, "0x", NATIVE, 0, metadata, poolManagers);
    }

    function test_createPoolWithBaseFee() public {
        uint256 baseFee = 1e17;

        allo().updateBaseFee(baseFee);

        vm.expectEmit(true, false, false, true);
        emit BaseFeePaid(1, baseFee);

        vm.deal(address(pool_admin()), 1e18);

        vm.prank(pool_admin());
        allo().createPoolWithCustomStrategy{value: 1e17}(
            poolProfile_id(), strategy, "0x", NATIVE, 0, metadata, pool_managers()
        );
    }

    function testRevert_createPool_withBaseFee_NOT_ENOUGH_FUNDS() public {
        uint256 baseFee = 1e17;
        allo().updateBaseFee(baseFee);

        vm.expectRevert(NOT_ENOUGH_FUNDS.selector);
        _utilCreatePool(0);
    }

    function test_createPool_WithAmount() public {
        vm.expectEmit(true, false, false, true);
        emit PoolCreated(1, poolProfile_id(), IStrategy(strategy), address(token), 10 * 10 ** 18, metadata);

        uint256 poolId = _utilCreatePool(10 * 10 ** 18);

        IAllo.Pool memory pool = allo().getPool(poolId);

        assertEq(pool.profileId, poolProfile_id());
        assertEq(address(pool.strategy), strategy);
    }

    function test_updatePoolMetadata() public {
        uint256 poolId = _utilCreatePool(0);

        Metadata memory updatedMetadata = Metadata({protocol: 1, pointer: "updated metadata"});

        vm.expectEmit(true, false, false, true);
        emit PoolMetadataUpdated(poolId, updatedMetadata);

        // update the metadata
        vm.prank(pool_admin());
        allo().updatePoolMetadata(poolId, updatedMetadata);

        // check that the metadata was updated
        Allo.Pool memory pool = allo().getPool(poolId);
        Metadata memory poolMetadata = pool.metadata;

        assertEq(poolMetadata.protocol, updatedMetadata.protocol);
        assertEq(poolMetadata.pointer, updatedMetadata.pointer);
    }

    function testRevert_updatePoolMetadata_UNAUTHORIZED() public {
        uint256 poolId = _utilCreatePool(0);
        vm.expectRevert(UNAUTHORIZED.selector);

        vm.prank(makeAddr("not owner"));
        allo().updatePoolMetadata(poolId, metadata);
    }

    function test_updateRegistry() public {
        vm.expectEmit(true, false, false, false);
        address payable newRegistry = payable(makeAddr("new registry"));
        emit RegistryUpdated(newRegistry);

        allo().updateRegistry(newRegistry);

        assertEq(address(allo().getRegistry()), newRegistry);
    }

    function testRevert_updateRegistry_UNAUTHORIZED() public {
        address payable newRegistry = payable(makeAddr("new registry"));
        // expect revert from solady
        vm.expectRevert();

        vm.prank(makeAddr("not owner"));
        allo().updateRegistry(newRegistry);
    }

    function testRevert_updateRegistry_ZERO_ADDRESS() public {
        vm.expectRevert(ZERO_ADDRESS.selector);
        allo().updateRegistry(address(0));
    }

    function test_updateTreasury() public {
        vm.expectEmit(true, false, false, false);
        address payable newTreasury = payable(makeAddr("new treasury"));
        emit TreasuryUpdated(newTreasury);

        allo().updateTreasury(newTreasury);

        assertEq(allo().getTreasury(), newTreasury);
    }

    function testRevert_updateTreasury_ZERO_ADDRESS() public {
        vm.expectRevert(ZERO_ADDRESS.selector);
        allo().updateTreasury(payable(address(0)));
    }

    function testRevert_updateTreasury_UNAUTHORIZED() public {
        address payable newTreasury = payable(makeAddr("new treasury"));

        // expect revert from solady
        vm.expectRevert();

        vm.prank(makeAddr("anon"));
        allo().updateTreasury(newTreasury);
    }

    function test_updatePercentFee() public {
        vm.expectEmit(true, false, false, false);

        uint256 newFee = 1e17;
        emit PercentFeeUpdated(newFee);

        allo().updatePercentFee(newFee);

        assertEq(allo().getPercentFee(), newFee);
    }

    function test_updatePercentFee_INVALID_FEE() public {
        vm.expectRevert(INVALID_FEE.selector);
        allo().updatePercentFee(2 * 1e18);
    }

    function testRevert_updatePercentFee_UNAUTHORIZED() public {
        vm.expectRevert();

        vm.prank(makeAddr("anon"));
        allo().updatePercentFee(2000);
    }

    function test_updateBaseFee() public {
        vm.expectEmit(true, false, false, false);

        uint256 newBaseFee = 1e17;
        emit BaseFeeUpdated(newBaseFee);

        allo().updateBaseFee(newBaseFee);

        assertEq(allo().getBaseFee(), newBaseFee);
    }

    function test_updateBaseFee_UNAUTHORIZED() public {
        vm.expectRevert();

        vm.prank(makeAddr("anon"));
        allo().updateBaseFee(1e16);
    }

    function test_addToCloneableStrategies() public {
        address _strategy = makeAddr("strategy");
        assertFalse(allo().isCloneableStrategy(_strategy));
        allo().addToCloneableStrategies(_strategy);
        assertTrue(allo().isCloneableStrategy(_strategy));
    }

    function testRevert_addToCloneableStrategies_ZERO_ADDRESS() public {
        vm.expectRevert(ZERO_ADDRESS.selector);
        allo().addToCloneableStrategies(address(0));
    }

    function testRevert_addToCloneableStrategies_UNAUTHORIZED() public {
        vm.expectRevert();
        vm.prank(makeAddr("anon"));
        address _strategy = makeAddr("strategy");
        allo().addToCloneableStrategies(_strategy);
    }

    function test_removeFromCloneableStrategies() public {
        address _strategy = makeAddr("strategy");
        allo().addToCloneableStrategies(_strategy);
        assertTrue(allo().isCloneableStrategy(_strategy));
        allo().removeFromCloneableStrategies(_strategy);
        assertFalse(allo().isCloneableStrategy(_strategy));
    }

    function testRevert_removeFromCloneableStrategies_UNAUTHORIZED() public {
        address _strategy = makeAddr("strategy");
        vm.expectRevert();
        vm.prank(makeAddr("anon"));
        allo().removeFromCloneableStrategies(_strategy);
    }

    function test_addPoolManager() public {
        uint256 poolId = _utilCreatePool(0);

        assertFalse(allo().isPoolManager(poolId, makeAddr("add manager")));
        vm.prank(pool_admin());
        allo().addPoolManager(poolId, makeAddr("add manager"));
        assertTrue(allo().isPoolManager(poolId, makeAddr("add manager")));
    }

    function testRevert_addPoolManager_UNAUTHORIZED() public {
        uint256 poolId = _utilCreatePool(0);
        vm.expectRevert(UNAUTHORIZED.selector);
        allo().addPoolManager(poolId, makeAddr("add manager"));
    }

    function testRevert_addPoolManager_ZERO_ADDRESS() public {
        uint256 poolId = _utilCreatePool(0);
        vm.expectRevert(ZERO_ADDRESS.selector);
        vm.prank(pool_admin());
        allo().addPoolManager(poolId, address(0));
    }

    function test_removePoolManager() public {
        uint256 poolId = _utilCreatePool(0);

        assertTrue(allo().isPoolManager(poolId, pool_manager1()));
        vm.prank(pool_admin());
        allo().removePoolManager(poolId, pool_manager1());
        assertFalse(allo().isPoolManager(poolId, pool_manager1()));
    }

    function testRevert_removePoolManager_UNAUTHORIZED() public {
        uint256 poolId = _utilCreatePool(0);
        vm.expectRevert(UNAUTHORIZED.selector);
        allo().removePoolManager(poolId, makeAddr("add manager"));
    }

    function test_recoverFunds() public {
        address user = makeAddr("recipient");

        vm.deal(address(allo()), 1e18);
        assertEq(address(allo()).balance, 1e18);
        assertEq(user.balance, 0);

        allo().recoverFunds(NATIVE, user);

        assertEq(address(allo()).balance, 0);
        assertNotEq(user.balance, 0);
    }

    function test_recoverFunds_ERC20() public {
        uint256 amount = 100;
        token.mint(address(allo()), amount);
        address user = address(0xBBB);

        assertEq(token.balanceOf(address(allo())), amount, "amount");
        assertEq(token.balanceOf(user), 0, "amount");

        allo().recoverFunds(address(token), user);

        assertEq(token.balanceOf(address(allo())), 0, "amount");
        assertEq(token.balanceOf(user), amount, "amount");
    }

    function testRevert_recoverFunds_UNAUTHORIZED() public {
        vm.expectRevert();
        vm.prank(makeAddr("anon"));
        allo().recoverFunds(address(0), makeAddr("recipient"));
    }

    function test_registerRecipient() public {
        uint256 poolId = _utilCreatePool(0);

        // apply to the pool
        allo().registerRecipient(poolId, bytes(""));
    }

    function test_batchRegisterRecipient() public {
        uint256[] memory poolIds = new uint256[](2);

        poolIds[0] = _utilCreatePool(0);

        address mockStrategy = address(new MockStrategy(address(allo())));
        vm.prank(pool_admin());
        poolIds[1] = allo().createPoolWithCustomStrategy(
            poolProfile_id(), mockStrategy, "0x", address(token), 0, metadata, pool_managers()
        );

        bytes[] memory datas = new bytes[](2);
        datas[0] = bytes("data1");
        datas[1] = "data2";
        // batch register to the pool should not revert
        allo().batchRegisterRecipient(poolIds, datas);
    }

    function testRevert_batchRegister_MISMATCH() public {
        uint256[] memory poolIds = new uint256[](2);

        poolIds[0] = _utilCreatePool(0);

        address mockStrategy = address(new MockStrategy(address(allo())));
        vm.prank(pool_admin());
        poolIds[1] = allo().createPoolWithCustomStrategy(
            poolProfile_id(), mockStrategy, "0x", address(token), 0, metadata, pool_managers()
        );

        bytes[] memory datas = new bytes[](1);
        datas[0] = bytes("data1");

        vm.expectRevert(MISMATCH.selector);

        allo().batchRegisterRecipient(poolIds, datas);
    }

    function test_fundPool() public {
        uint256 poolId = _utilCreatePool(0);

        vm.expectEmit(true, false, false, true);
        emit PoolFunded(poolId, 9.9e19, 1e18);

        allo().fundPool(poolId, 10 * 10e18);
    }

    function testRevert_fundPool_NOT_ENOUGH_FUNDS() public {
        uint256 poolId = _utilCreatePool(0);

        vm.prank(makeAddr("broke chad"));
        vm.expectRevert(NOT_ENOUGH_FUNDS.selector);

        allo().fundPool(poolId, 0);
    }

    function test_allocate() public {
        uint256 poolId = _utilCreatePool(0);
        // allocate to the pool should not revert
        allo().allocate(poolId, bytes(""));
    }

    function test_batchAllocate() public {
        uint256[] memory poolIds = new uint256[](2);

        poolIds[0] = _utilCreatePool(0);

        address mockStrategy = address(new MockStrategy(address(allo())));
        vm.prank(pool_admin());
        poolIds[1] = allo().createPoolWithCustomStrategy(
            poolProfile_id(), mockStrategy, "0x", address(token), 0, metadata, pool_managers()
        );

        bytes[] memory datas = new bytes[](2);
        datas[0] = bytes("data1");
        datas[1] = "data2";
        // allocate to the pool should not revert
        allo().batchAllocate(poolIds, datas);
    }

    function testRevert_batchAllocate_MISMATCH() public {
        uint256[] memory poolIds = new uint256[](2);

        poolIds[0] = _utilCreatePool(0);

        address mockStrategy = address(new MockStrategy(address(allo())));
        vm.prank(pool_admin());
        poolIds[1] = allo().createPoolWithCustomStrategy(
            poolProfile_id(), mockStrategy, "0x", address(token), 0, metadata, pool_managers()
        );

        bytes[] memory datas = new bytes[](1);
        datas[0] = bytes("data1");

        vm.expectRevert(MISMATCH.selector);

        allo().batchAllocate(poolIds, datas);
    }

    function test_distribute() public {
        uint256 poolId = _utilCreatePool(0);
        // distribution to the pool should not revert
        address[] memory recipientIds = new address[](1);
        allo().distribute(poolId, recipientIds, bytes(""));
    }

    function test_isPoolAdmin() public {
        uint256 poolId = _utilCreatePool(0);

        assertTrue(allo().isPoolAdmin(poolId, pool_admin()));
        assertFalse(allo().isPoolAdmin(poolId, makeAddr("not admin")));
    }

    function test_isPoolManager() public {
        uint256 poolId = _utilCreatePool(0);

        assertTrue(allo().isPoolManager(poolId, pool_manager1()));
        assertFalse(allo().isPoolManager(poolId, makeAddr("not manager")));
    }

    function test_getStartegy() public {
        uint256 poolId = _utilCreatePool(0);

        assertEq(address(allo().getStrategy(poolId)), strategy);
    }

     function testFundPoolWithExactBaseFee() public {
        // Test funding with exact base fee amount
        uint256 baseFee = 1e17;
        allo().updateBaseFee(baseFee);

        vm.deal(address(pool_admin()), baseFee);
        vm.prank(pool_admin());

        uint256 poolId = allo().createPoolWithCustomStrategy{value: baseFee}(
            poolProfile_id(),
            strategy,
            "0x",
            NATIVE,
            0,
            metadata,
            pool_managers()
        );

        assertEq(address(allo_treasury()).balance, baseFee);
    }

    function testMultipleManagerRoleRevocation() public {
        uint256 poolId = _utilCreatePool(0);
        address newManager = makeAddr("new_manager");
        
        vm.startPrank(pool_admin());
        allo().addPoolManager(poolId, newManager);
        allo().addPoolManager(poolId, newManager);
        allo().removePoolManager(poolId, newManager);
        vm.stopPrank();

        assertFalse(allo().isPoolManager(poolId, newManager));
    }

    function testPoolFundingWithTinyAmounts() public {
        uint256 poolId = _utilCreatePool(0);
        uint256 tinyAmount = 1;

        token.mint(address(this), tinyAmount);
        token.approve(address(allo()), tinyAmount);

        allo().fundPool(poolId, tinyAmount);

        uint256 expectedFee = (tinyAmount * allo().getPercentFee()) / allo().getFeeDenominator();
        assertEq(token.balanceOf(allo_treasury()), expectedFee);
    }

    function testReentrantPoolFunding() public {
        // Create a pool with native token
        vm.prank(pool_admin());
        uint256 poolId = allo().createPoolWithCustomStrategy(
            poolProfile_id(),
            strategy,
            "0x",
            NATIVE,
            0,
            metadata,
            new address[](0)
        );

        MockReentrantStrategy reentrantStrategy = new MockReentrantStrategy(address(allo()));
        vm.deal(address(reentrantStrategy), 2 ether);
        
        vm.expectRevert();
        reentrantStrategy.attack(poolId);
    }

    function testRecoverFundsWithDustAmount() public {
        uint256 dustAmount = 1;
        token.mint(address(allo()), dustAmount);
        
        address recipient = makeAddr("recipient");
        uint256 balanceBefore = token.balanceOf(recipient);
        
        allo().recoverFunds(address(token), recipient);
        
        assertEq(token.balanceOf(recipient), balanceBefore + dustAmount);
        assertEq(token.balanceOf(address(allo())), 0);
    }

    function testFeeCalculationWithMaxValues() public {
        uint256 poolId = _utilCreatePool(0);
        uint256 maxAmount = type(uint256).max / allo().getFeeDenominator();

        token.mint(address(this), maxAmount);
        token.approve(address(allo()), maxAmount);

        allo().fundPool(poolId, maxAmount);

        uint256 expectedFee = (maxAmount * allo().getPercentFee()) / allo().getFeeDenominator();
        assertTrue(expectedFee > 0, "Fee should be non-zero for large amounts");
    }

    function testDistributeWithEmptyRecipientsArray() public {
        uint256 poolId = _utilCreatePool(0);
        address[] memory emptyRecipients = new address[](0);
        
        // Should not revert with empty recipients array
        allo().distribute(poolId, emptyRecipients, "");
    }

    function testPoolCreationWithMaxStrategyData() public {
        bytes memory largeData = new bytes(1000000); // Large initialization data
        
        vm.prank(pool_admin());
        uint256 poolId = allo().createPoolWithCustomStrategy(
            poolProfile_id(),
            strategy,
            largeData,
            NATIVE,
            0,
            metadata,
            pool_managers()
        );

        assertTrue(poolId > 0, "Pool should be created with large strategy data");
    }

    function testFundPoolRaceCondition() public {
        // First create pool
        uint256 poolId = _utilCreatePool(0);
        uint256 amount = 100 ether;
        
        // Set up multiple actors
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        
        // Give them funds and approve tokens
        token.mint(alice, amount);
        token.mint(bob, amount);
        
        vm.prank(alice);
        token.approve(address(allo()), amount);
        
        vm.prank(bob);
        token.approve(address(allo()), amount);
        
        // Try to fund pool from multiple actors
        vm.prank(alice);
        allo().fundPool(poolId, amount);
        
        vm.prank(bob);
        allo().fundPool(poolId, amount);
        
        // Verify total pool amount is correct
        uint256 expectedTotal = (amount * 2) - ((amount * 2 * allo().getPercentFee()) / allo().getFeeDenominator());
        assertEq(token.balanceOf(address(strategy)), expectedTotal);
    }
function testOwnershipTransferSecurity() public {
    address newOwner = makeAddr("newOwner");
    address attacker = makeAddr("attacker");
    
    // Record initial owner
    address initialOwner = local();
    
    // Attacker tries to transfer ownership
    vm.prank(attacker);
    vm.expectRevert();
    allo().transferOwnership(attacker);
    
    // Verify ownership didn't change
    assertEq(allo().owner(), initialOwner);
    
    // Legitimate owner transfer
    vm.prank(initialOwner);
    allo().transferOwnership(newOwner);
    
    // Verify new ownership
    assertEq(allo().owner(), newOwner);
    
    // Attacker tries to transfer ownership after transfer
    vm.prank(attacker);
    vm.expectRevert();
    allo().transferOwnership(attacker);
    
    // Previous owner tries to transfer ownership
    vm.prank(initialOwner);
    vm.expectRevert();
    allo().transferOwnership(initialOwner);
}

function testOwnershipRenounce() public {
    // Attacker tries to renounce ownership
    vm.prank(makeAddr("attacker"));
    vm.expectRevert();
    allo().renounceOwnership();
    
    // Owner can renounce ownership
    vm.prank(local());
    allo().renounceOwnership();
    
    // Verify ownership is renounced
    assertEq(allo().owner(), address(0));
    
    // Try operations after renouncing
    address newTreasury = makeAddr("newTreasury");
    vm.prank(local());
    vm.expectRevert();
    allo().updateTreasury(payable(newTreasury));
}

function testDirectOwnershipManipulation() public {
    // Try accessing internal _owner variable (if it exists)
    vm.expectRevert();
    (bool success,) = address(allo()).call(
        abi.encodeWithSignature("_owner()")
    );
    assertFalse(success);
    
    // Try force transfer via storage manipulation
    vm.store(
        address(allo()),
        bytes32(uint256(0)), // slot where owner might be stored
        bytes32(uint256(uint160(makeAddr("attacker"))))
    );
    
    // Verify ownership unchanged
    assertEq(allo().owner(), local());
}

function testTransferToZeroAddress() public {
    // Try to transfer ownership to zero address
    vm.prank(local());
    vm.expectRevert();
    allo().transferOwnership(address(0));
    
    // Verify ownership unchanged
    assertEq(allo().owner(), local());
}

function testMultipleOwnershipTransfers() public {
    address[] memory newOwners = new address[](3);
    newOwners[0] = makeAddr("owner1");
    newOwners[1] = makeAddr("owner2");
    newOwners[2] = makeAddr("owner3");
    
    // Transfer ownership multiple times
    for(uint256 i = 0; i < newOwners.length; i++) {
        vm.prank(i == 0 ? local() : newOwners[i-1]);
        allo().transferOwnership(newOwners[i]);
        assertEq(allo().owner(), newOwners[i]);
    }
    
    // Verify old owners can't perform privileged actions
    vm.prank(local());
    vm.expectRevert();
    allo().updateBaseFee(1 ether);
    
    vm.prank(newOwners[0]);
    vm.expectRevert();
    allo().updateBaseFee(1 ether);
}
function testFeeCalculationPrecision() public {
    uint256 poolId = _utilCreatePool(0);
    uint256 tinyAmount = 1000; // Small amount to test precision
    
    // Calculate expected fee with full precision
    uint256 expectedFee = (tinyAmount * allo().getPercentFee()) / allo().getFeeDenominator();
    uint256 expectedAmountAfterFee = tinyAmount - expectedFee;
    
    token.mint(address(this), tinyAmount);
    token.approve(address(allo()), tinyAmount);
    
    allo().fundPool(poolId, tinyAmount);
    
    // Check if rounding errors occur
    assertEq(token.balanceOf(address(strategy)), expectedAmountAfterFee, "Amount after fee should match expected");
    assertEq(token.balanceOf(allo_treasury()), expectedFee, "Fee should match expected");
}

function testStrategyDoubleInitialization() public {
    bytes32 profileId = bytes32(uint256(1));
    address[] memory managers = new address[](0);
    
    // Create first pool
    vm.prank(pool_admin());
    uint256 poolId1 = allo().createPoolWithCustomStrategy(
        profileId,
        address(strategy),
        "0x",
        NATIVE,
        0,
        metadata,
        managers
    );

    // Try to reinitialize same strategy
    vm.prank(pool_admin());
    vm.expectRevert();
    allo().createPoolWithCustomStrategy(
        profileId,
        address(strategy),
        "0x",
        NATIVE,
        0,
        metadata,
        managers
    );
}

function testPoolIdPredictability() public {
    uint256 firstPoolId = _utilCreatePool(0);
    uint256 secondPoolId = _utilCreatePool(0);
    uint256 thirdPoolId = _utilCreatePool(0);
    
    // Verify IDs are sequential
    assertEq(secondPoolId, firstPoolId + 1);
    assertEq(thirdPoolId, secondPoolId + 1);
}


function testFeeTokenTransferSafety() public {
    // Deploy malicious token that only returns false on transfers
    MaliciousToken malToken = new MaliciousToken();
    
    vm.prank(pool_admin());
    uint256 poolId = allo().createPoolWithCustomStrategy(
        poolProfile_id(),
        strategy,
        "0x",
        address(malToken),
        0,
        metadata,
        pool_managers()
    );
    
    malToken.mint(address(this), 1000);
    malToken.approve(address(allo()), 1000);
    
    // Should revert on transfer failure
    vm.expectRevert();
    allo().fundPool(poolId, 1000);
}

 function testMaliciousRegistryUpdate() public {
        address maliciousRegistry = makeAddr("maliciousRegistry");

        // Try to update registry from non-owner
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        allo().updateRegistry(maliciousRegistry);

        // Update from legitimate owner
        vm.startPrank(local());
        allo().updateRegistry(maliciousRegistry);
        assertEq(address(allo().getRegistry()), maliciousRegistry);
        vm.stopPrank();
    }

    function testFeeCalculationPrecisionLoss() public {
        uint256 poolId = _utilCreatePool(0);
        
        // Test with very small amounts to check for precision loss
        uint256[] memory testAmounts = new uint256[](3);
        testAmounts[0] = 100;
        testAmounts[1] = 101;  // Prime number
        testAmounts[2] = 1001; // Odd number
        
        for(uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            token.mint(address(this), amount);
            token.approve(address(allo()), amount);
            
            uint256 expectedFee = (amount * allo().getPercentFee()) / allo().getFeeDenominator();
            uint256 expectedAfterFee = amount - expectedFee;
            
            vm.recordLogs();
            allo().fundPool(poolId, amount);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            
            // Verify amounts from events
            assertEq(token.balanceOf(address(strategy)), expectedAfterFee, "Amount after fee mismatch");
            assertEq(token.balanceOf(allo_treasury()), expectedFee, "Fee amount mismatch");
        }
    }

    function testDoubleInitializationStrategy() public {
        bytes32 profileId = bytes32(uint256(1));
        address[] memory managers = new address[](0);
        
        // Create mock strategy that allows reinitialization
        MockReentrantStrategy mockStrat = new MockReentrantStrategy(address(allo()));
        
        // Create first pool
        vm.prank(pool_admin());
        uint256 poolId1 = allo().createPoolWithCustomStrategy(
            profileId,
            address(mockStrat),
            "0x",
            NATIVE,
            0,
            metadata,
            managers
        );

        // Try to create another pool with same strategy
        vm.prank(pool_admin());
        vm.expectRevert();
        allo().createPoolWithCustomStrategy(
            profileId,
            address(mockStrat),
            "0x",
            NATIVE,
            0,
            metadata,
            managers
        );
    }

    function testManagerRoleSeparation() public {
        uint256 poolId1 = _utilCreatePool(0);
        uint256 poolId2 = _utilCreatePool(0);
        
        address manager = makeAddr("manager");
        
        // Add manager to pool1
        vm.prank(pool_admin());
        allo().addPoolManager(poolId1, manager);
        
        // Verify manager only has access to pool1
        assertTrue(allo().isPoolManager(poolId1, manager));
        assertFalse(allo().isPoolManager(poolId2, manager));
        
        // Try to use manager powers on pool2
        vm.startPrank(manager);
        Metadata memory newMetadata = Metadata({protocol: 1, pointer: "new"});
        
        // Should succeed for pool1
        allo().updatePoolMetadata(poolId1, newMetadata);
        
        // Should fail for pool2
        vm.expectRevert();
        allo().updatePoolMetadata(poolId2, newMetadata);
        vm.stopPrank();
    }

    function testStrategyInitializationWithLargeData() public {
        // Create large initialization data
        bytes memory largeData = new bytes(50000);
        for(uint i = 0; i < largeData.length; i++) {
            largeData[i] = 0xFF;
        }
        
        // Try to create pool with large initialization data
        vm.prank(pool_admin());
        uint256 poolId = allo().createPoolWithCustomStrategy(
            poolProfile_id(),
            strategy,
            largeData,
            NATIVE,
            0,
            metadata,
            pool_managers()
        );

        assertTrue(poolId > 0, "Pool should be created with large init data");
    }

   function testRecoverFundsAfterForceEther() public {
    // Force send ether to contract using selfdestruct
    ForceSendEther forceSend = new ForceSendEther();
    vm.deal(address(forceSend), 1 ether);
    forceSend.forceSend(payable(address(allo()))); // Fix: Convert to payable address

    // Verify balance
    assertEq(address(allo()).balance, 1 ether);

    // Try to recover as non-owner (should fail)
    address recipient = makeAddr("recipient");
    vm.prank(makeAddr("attacker"));
    vm.expectRevert();
    allo().recoverFunds(NATIVE, recipient);

    // Recover as owner
    vm.prank(local());
    allo().recoverFunds(NATIVE, recipient);
    
    // Verify recovery
    assertEq(address(allo()).balance, 0);
    assertEq(recipient.balance, 1 ether);
}
}



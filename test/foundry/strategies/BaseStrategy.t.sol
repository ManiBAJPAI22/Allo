// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {Errors} from "../../../contracts/core/libraries/Errors.sol";
import {AlloSetup} from "../shared/AlloSetup.sol";
import {RegistrySetupFull} from "../shared/RegistrySetup.sol";
import {MockStrategy} from "../../utils/MockStrategy.sol";
import {IStrategy} from "../../../contracts/core/interfaces/IStrategy.sol";

// Create a malicious strategy to test attacks
contract MaliciousStrategy is MockStrategy {
    bool internal _attacking;
    uint256 internal _attackCount;

    constructor(address _allo) MockStrategy(_allo) {}

    // Setter functions
    function setAttacking(bool attacking_) external {
        _attacking = attacking_;
    }

    function getAttackCount() external view returns (uint256) {
        return _attackCount;
    }

    // Try to reenter during distribution
    function _beforeDistribute(address[] memory, bytes memory, address) internal override {
        if (_attacking) {
            _attackCount++;
            // Try to distribute again
            address[] memory recipients = new address[](1);
            allo.distribute(1, recipients, "");
        }
    }

    // Try to manipulate pool amount
    function _afterIncreasePoolAmount(uint256) internal override {
        if (_attacking) {
            // Try to increase pool amount again
            allo.fundPool(1, 100);
        }
    }
}

contract BaseStrategyTest is Test, AlloSetup, RegistrySetupFull, Errors {
    MockStrategy strategy;
    MaliciousStrategy malStrategy;

    function setUp() public {
        __RegistrySetupFull();
        __AlloSetup(address(registry()));

        strategy = new MockStrategy(address(allo()));
        malStrategy = new MaliciousStrategy(address(allo()));
    }

    // Test reentrancy protection
    function testDistributionReentrancy() public {
        vm.startPrank(address(allo()));
        malStrategy.initialize(1, "");
        malStrategy.setAttacking(true);
        
        address[] memory recipients = new address[](1);
        
        // Should fail if reentrancy is attempted
        vm.expectRevert();
        malStrategy.distribute(recipients, "", address(this));
        
        assertEq(malStrategy.getAttackCount(), 0, "Reentrancy attack succeeded");
        vm.stopPrank();
    }

    // Test pool amount manipulation protection
    function testPoolAmountManipulation() public {
        vm.startPrank(address(allo()));
        malStrategy.initialize(1, "");
        malStrategy.setAttacking(true);
        
        uint256 initialAmount = malStrategy.getPoolAmount();
        malStrategy.increasePoolAmount(100);
        
        // Amount should only increase once
        assertEq(malStrategy.getPoolAmount(), initialAmount + 100, "Pool amount was manipulated");
        vm.stopPrank();
    }

    // Test for unauthorized status changes
    function testUnauthorizedStatusChange() public {
        vm.prank(address(allo()));
        strategy.initialize(1, "");

        address randomUser = makeAddr("random");
        vm.prank(randomUser);
        
        // Should revert when unauthorized user tries to change status
        vm.expectRevert();
        strategy.setPoolActive(true);
    }

    // Test for invalid initialization
    function testInvalidInitialization() public {
        // Try to initialize with zero address allo
        MockStrategy invalidStrategy = new MockStrategy(address(0));
        
        // Should fail on any operation
        vm.expectRevert();
        invalidStrategy.initialize(1, "");
    }

    // Test hook function manipulation
    function testHookFunctionManipulation() public {
        vm.startPrank(address(allo()));
        
        // Initialize strategy
        strategy.initialize(1, "");
        
        // Try to manipulate state in hooks
        bytes memory data = "";
        address sender = address(this);
        
        vm.expectRevert();
        strategy.registerRecipient(data, sender);
        
        vm.expectRevert();
        strategy.allocate(data, sender);
        
        vm.stopPrank();
    }

    // Test for fund drainage
    function testFundDrainageProtection() public {
        vm.startPrank(address(allo()));
        strategy.initialize(1, "");
        
        // Fund the strategy
        strategy.increasePoolAmount(1000);
        
        address[] memory recipients = new address[](1);
        recipients[0] = address(this);
        
        // Try to distribute more than available
        bytes memory largeAmountData = abi.encode(uint256(2000));
        
        vm.expectRevert();
        strategy.distribute(recipients, largeAmountData, address(this));
        
        vm.stopPrank();
    }

    // Test for sequential operations protection
    function testSequentialOperationsProtection() public {
        vm.startPrank(address(allo()));
        strategy.initialize(1, "");
        
        // Try to perform operations out of order
        address[] memory recipients = new address[](1);
        
        // Try to distribute before allocation
        vm.expectRevert();
        strategy.distribute(recipients, "", address(this));
        
        vm.stopPrank();
    }

    // Test access control after status changes
    function testAccessControlAfterStatusChange() public {
        vm.prank(address(allo()));
        strategy.initialize(1, "");
        
        // Set pool as inactive
        strategy.setPoolActive(false);
        
        // Operations should fail when pool is inactive
        vm.expectRevert();
        strategy.registerRecipient("", address(this));
    }

    // Test for initialization replay
    function testInitializationReplay() public {
        vm.startPrank(address(allo()));
        strategy.initialize(1, "");
        
        // Try to initialize again
        vm.expectRevert();
        strategy.initialize(1, "");
        
        vm.stopPrank();
    }
}
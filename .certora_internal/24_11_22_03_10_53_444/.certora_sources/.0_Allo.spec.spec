pragma solidity 0.8.19;

ruleset AlloRules {
    // Rule 1: Only the owner can call `updateRegistry`, `updateTreasury`, `updatePercentFee`, and `updateBaseFee`.
    rule OnlyOwnerCanUpdateConfiguration() {
        // Preconditions
        address caller = msg.sender;
        
        // Allowed functions
        requires calldata == Allo.updateRegistry.selector ||
                 calldata == Allo.updateTreasury.selector ||
                 calldata == Allo.updatePercentFee.selector ||
                 calldata == Allo.updateBaseFee.selector;

        // Check ownership
        assert owner == caller;
    }

    // Rule 2: Pool metadata can only be updated by the pool manager.
    rule OnlyPoolManagerCanUpdateMetadata(uint256 _poolId) {
        // Preconditions
        address caller = msg.sender;
        requires calldata == Allo.updatePoolMetadata.selector;

        // Check pool manager role
        assert hasRole(pools[_poolId].managerRole, caller) || 
               hasRole(pools[_poolId].adminRole, caller);
    }

    // Rule 3: `createPoolWithCustomStrategy` must fail if `_strategy` is not set.
    rule CreatePoolWithCustomStrategyFailsWithoutStrategy() {
        // Preconditions
        address strategy = args[1]; // _strategy

        // Check invalid input
        requires strategy == address(0);

        // Expect revert
        assert revert();
    }

    // Rule 4: `createPool` and `createPoolWithCustomStrategy` should increment `_poolIndex`.
    rule PoolIndexIncrementsOnCreatePool(uint256 initialPoolIndex) {
        // Preconditions
        uint256 poolIndexBefore = _poolIndex;
        requires calldata == Allo.createPool.selector || calldata == Allo.createPoolWithCustomStrategy.selector;

        // Effect
        uint256 poolIndexAfter = _poolIndex;
        assert poolIndexAfter == poolIndexBefore + 1;
    }

    // Rule 5: Fee percentages cannot exceed 100% (1e18).
    rule PercentFeeMustBeValid(uint256 _percentFee) {
        // Preconditions
        requires calldata == Allo.updatePercentFee.selector;

        // Valid percentage
        assert _percentFee <= 1e18;
    }

    // Rule 6: Base fee cannot be negative or non-payable if set.
    rule BaseFeeCannotBeInvalid(uint256 _baseFee) {
        // Preconditions
        requires calldata == Allo.updateBaseFee.selector;

        // Base fee check
        assert _baseFee >= 0;
    }

    // Rule 7: Treasury address must not be zero.
    rule TreasuryAddressCannotBeZero(address treasury) {
        // Preconditions
        requires calldata == Allo.updateTreasury.selector;

        // Check for zero address
        assert treasury != address(0);
    }

    // Rule 8: A funded pool's balance should reflect the sum of its funding minus fees.
    rule PoolBalanceCorrectOnFunding(uint256 _poolId, uint256 _amount, uint256 percentFee) {
        // Preconditions
        Pool storage pool = pools[_poolId];
        uint256 balanceBefore = _getBalance(pool.token, address(pool.strategy));
        uint256 expectedFee = (_amount * percentFee) / 1e18;

        // Effects
        requires calldata == Allo.fundPool.selector;
        uint256 balanceAfter = _getBalance(pool.token, address(pool.strategy));
        assert balanceAfter == balanceBefore + (_amount - expectedFee);
    }

    // Rule 9: Only approved strategies can be cloned for pools.
    rule StrategyMustBeCloneable(address strategy) {
        // Preconditions
        requires calldata == Allo.createPool.selector;

        // Check strategy cloneable status
        assert cloneableStrategies[strategy];
    }

    // Rule 10: Only pool admins can add or remove pool managers.
    rule OnlyAdminsCanManagePoolManagers(uint256 _poolId, address manager) {
        // Preconditions
        address caller = msg.sender;
        requires calldata == Allo.addPoolManager.selector || calldata == Allo.removePoolManager.selector;

        // Admin role check
        assert hasRole(pools[_poolId].adminRole, caller);
    }

    // Rule 11: When creating a pool, `_managers` cannot include the zero address.
    rule PoolManagersCannotBeZeroAddress(uint256 _poolId, address[] memory _managers) {
        // Preconditions
        requires calldata == Allo.createPool.selector || calldata == Allo.createPoolWithCustomStrategy.selector;

        // Validate manager addresses
        for (uint256 i = 0; i < _managers.length; i++) {
            assert _managers[i] != address(0);
        }
    }

    // Rule 12: The pool ID returned after creation must map to a valid pool.
    rule ValidPoolIDOnCreation(uint256 poolId) {
        // Preconditions
        requires calldata == Allo.createPool.selector || calldata == Allo.createPoolWithCustomStrategy.selector;

        // Valid pool mapping
        assert pools[poolId].token != address(0);
    }
}



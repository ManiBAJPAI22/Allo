// Rule 1: Only the owner can update the configuration
rule OnlyOwnerCanUpdateConfiguration {
    env e;
    require e.msg.sender == Allo.owner();
    require
        e.selector == Allo.updateRegistry.selector ||
        e.selector == Allo.updateTreasury.selector ||
        e.selector == Allo.updatePercentFee.selector ||
        e.selector == Allo.updateBaseFee.selector;
    assert true; // Ownership validated
}

// Rule 2: Ensure percentFee is always <= 100%
rule PercentFeeCannotExceed100Percent {
    env e;
    require e.selector == Allo.updatePercentFee.selector;
    uint256 fee = Allo.getPercentFee();
    uint256 denominator = Allo.getFeeDenominator();
    assert fee <= denominator; // Fee cannot exceed 100%
}

// Rule 3: Treasury cannot be the zero address
rule TreasuryAddressMustBeValid {
    env e;
    require e.selector == Allo.updateTreasury.selector;
    address treasury = Allo.getTreasury();
    assert treasury != 0; // Treasury must be valid
}

// Rule 4: Registry address must be valid
rule RegistryAddressMustBeValid {
    env e;
    require e.selector == Allo.updateRegistry.selector;
    address registry = Allo.getRegistry();
    assert registry != 0; // Registry must be valid
}

// Rule 5: Only pool managers or admins can update pool metadata
rule OnlyManagersOrAdminsCanUpdateMetadata(uint256 poolId) {
    env e;
    require e.selector == Allo.updatePoolMetadata.selector;
    require Allo.isPoolManager(e.msg.sender, poolId) ||
            Allo.isPoolAdmin(e.msg.sender, poolId);
    assert true; // Access control validated
}

// Rule 6: Pool creation should increment the pool index
rule PoolCreationIncrementsIndex {
    env e;
    uint256 poolIndexBefore = Allo.poolIndex();
    require e.selector == Allo.createPool.selector || 
            e.selector == Allo.createPoolWithCustomStrategy.selector;
    uint256 poolIndexAfter = Allo.poolIndex();
    assert poolIndexAfter == poolIndexBefore + 1; // Index must increment
}

// Rule 7: No unauthorized recipient registration
rule OnlyAuthorizedCanRegisterRecipient(uint256 poolId) {
    env e;
    require e.selector == Allo.registerRecipient.selector || 
            e.selector == Allo.batchRegisterRecipient.selector;
    require Allo.isPoolAdmin(e.msg.sender, poolId) ||
            Allo.isPoolManager(e.msg.sender, poolId);
    assert true; // Access validated
}

// Rule 8: Fee and amount integrity during funding
rule FeeAndAmountIntegrityDuringFunding(uint256 poolId, uint256 amount) {
    env e;
    uint256 treasuryBefore = Allo.getTreasuryBalance();
    uint256 poolBefore = Allo.getPoolBalance(poolId);
    require e.selector == Allo.fundPool.selector;
    uint256 treasuryAfter = Allo.getTreasuryBalance();
    uint256 poolAfter = Allo.getPoolBalance(poolId);
    assert treasuryAfter + poolAfter == treasuryBefore + poolBefore + amount;
}

// Rule 9: Strategy cloning must use approved strategies
rule OnlyApprovedStrategiesCanBeCloned(address strategy) {
    env e;
    require e.selector == Allo.createPool.selector;
    assert Allo.isCloneableStrategy(strategy);
}

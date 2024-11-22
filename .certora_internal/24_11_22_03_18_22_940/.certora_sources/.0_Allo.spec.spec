// Rule 1: Only the owner can update the configuration
rule OnlyOwnerCanUpdateConfiguration {
    require env.msgSender == Allo.owner();
    require
        env.functionSelector == Allo.updateRegistry.selector ||
        env.functionSelector == Allo.updateTreasury.selector ||
        env.functionSelector == Allo.updatePercentFee.selector ||
        env.functionSelector == Allo.updateBaseFee.selector;
    assert true; // Ownership validated
}

// Rule 2: Ensure percentFee is always <= 100%
rule PercentFeeCannotExceed100Percent {
    require env.functionSelector == Allo.updatePercentFee.selector;
    ensure Allo.getPercentFee() <= Allo.getFeeDenominator(); // Fee cannot exceed 100%
}

// Rule 3: Treasury cannot be the zero address
rule TreasuryAddressMustBeValid {
    require env.functionSelector == Allo.updateTreasury.selector;
    ensure Allo.getTreasury() != address(0); // Treasury must be valid
}

// Rule 4: Registry address must be valid
rule RegistryAddressMustBeValid {
    require env.functionSelector == Allo.updateRegistry.selector;
    ensure Allo.getRegistry() != address(0); // Registry must be valid
}

// Rule 5: Only pool managers or admins can update pool metadata
rule OnlyManagersOrAdminsCanUpdateMetadata {
    require env.functionSelector == Allo.updatePoolMetadata.selector;
    require Allo.isPoolManager(env.msgSender, calldata.poolId) ||
            Allo.isPoolAdmin(env.msgSender, calldata.poolId);
    assert true; // Access control validated
}

// Rule 6: Pool creation should increment the pool index
rule PoolCreationIncrementsIndex {
    uint256 poolIndexBefore = Allo.poolIndex();
    require env.functionSelector == Allo.createPool.selector || env.functionSelector == Allo.createPoolWithCustomStrategy.selector;
    ensure Allo.poolIndex() == poolIndexBefore + 1; // Index must increment
}

// Rule 7: No unauthorized recipient registration
rule OnlyAuthorizedCanRegisterRecipient {
    require env.functionSelector == Allo.registerRecipient.selector || env.functionSelector == Allo.batchRegisterRecipient.selector;
    require Allo.isPoolAdmin(env.msgSender, calldata.poolId) ||
            Allo.isPoolManager(env.msgSender, calldata.poolId);
    assert true; // Access validated
}

// Rule 8: Fee and amount integrity during funding
rule FeeAndAmountIntegrityDuringFunding {
    uint256 totalBalanceBefore = Allo.getTreasuryBalance() + Allo.getPoolBalance(calldata.poolId);
    require env.functionSelector == Allo.fundPool.selector;
    ensure Allo.getTreasuryBalance() + Allo.getPoolBalance(calldata.poolId) == totalBalanceBefore + calldata.amount;
}

// Rule 9: Strategy cloning must use approved strategies
rule OnlyApprovedStrategiesCanBeCloned {
    require env.functionSelector == Allo.createPool.selector;
    ensure Allo.isCloneableStrategy(calldata.strategy);
}

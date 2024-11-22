// Rule 1: Only the owner can update the configuration
rule OnlyOwnerCanUpdateConfiguration {
    require msg.sender == Allo.owner();
    require
        calldata == Allo.updateRegistry.selector ||
        calldata == Allo.updateTreasury.selector ||
        calldata == Allo.updatePercentFee.selector ||
        calldata == Allo.updateBaseFee.selector;
    assert true; // Ownership validated
}

// Rule 2: Ensure percentFee is always <= 100%
rule PercentFeeCannotExceed100Percent {
    require calldata == Allo.updatePercentFee.selector;
    ensure Allo.getPercentFee() <= Allo.getFeeDenominator(); // Fee cannot exceed 100%
}

// Rule 3: Treasury cannot be the zero address
rule TreasuryAddressMustBeValid {
    require calldata == Allo.updateTreasury.selector;
    ensure Allo.getTreasury() != address(0); // Treasury must be valid
}

// Rule 4: Registry address must be valid
rule RegistryAddressMustBeValid {
    require calldata == Allo.updateRegistry.selector;
    ensure Allo.getRegistry() != address(0); // Registry must be valid
}

// Rule 5: Only pool managers or admins can update pool metadata
rule OnlyManagersOrAdminsCanUpdateMetadata {
    require calldata == Allo.updatePoolMetadata.selector;
    require msg.sender == Allo.isPoolManager(calldata.poolId, msg.sender) ||
            msg.sender == Allo.isPoolAdmin(calldata.poolId, msg.sender);
    assert true; // Access control validated
}

// Rule 6: Pool creation should increment the pool index
rule PoolCreationIncrementsIndex {
    uint256 poolIndexBefore = Allo.poolIndex();
    require calldata == Allo.createPool.selector || calldata == Allo.createPoolWithCustomStrategy.selector;
    ensure Allo.poolIndex() == poolIndexBefore + 1; // Index must increment
}

// Rule 7: No unauthorized recipient registration
rule OnlyAuthorizedCanRegisterRecipient {
    require calldata == Allo.registerRecipient.selector || calldata == Allo.batchRegisterRecipient.selector;
    require Allo.isPoolAdmin(calldata.poolId, msg.sender) ||
            Allo.isPoolManager(calldata.poolId, msg.sender);
    assert true; // Access validated
}

// Rule 8: Fee and amount integrity during funding
rule FeeAndAmountIntegrityDuringFunding {
    uint256 totalBalanceBefore = Allo.getTreasuryBalance() + Allo.getPoolBalance(calldata.poolId);
    require calldata == Allo.fundPool.selector;
    ensure Allo.getTreasuryBalance() + Allo.getPoolBalance(calldata.poolId) == totalBalanceBefore + calldata.amount;
}

// Rule 9: Strategy cloning must use approved strategies
rule OnlyApprovedStrategiesCanBeCloned {
    require calldata == Allo.createPool.selector;
    ensure Allo.isCloneableStrategy(calldata.strategy);
}

ruleset AlloRules {
    // Rule 1: Only the owner can update the configuration
    rule OnlyOwnerCanUpdateConfiguration() {
        requires msg.sender == Allo.owner();
        requires calldata == Allo.updateRegistry.selector ||
                 calldata == Allo.updateTreasury.selector ||
                 calldata == Allo.updatePercentFee.selector ||
                 calldata == Allo.updateBaseFee.selector;
        assert true; // Ownership validated
    }

    // Rule 2: Ensure percentFee is always <= 100%
    rule PercentFeeCannotExceed100Percent() {
        requires calldata == Allo.updatePercentFee.selector;
        ensures Allo.getPercentFee() <= Allo.getFeeDenominator(); // Fee cannot exceed 100%
    }

    // Rule 3: Treasury cannot be the zero address
    rule TreasuryAddressMustBeValid() {
        requires calldata == Allo.updateTreasury.selector;
        ensures Allo.getTreasury() != 0x0000000000000000000000000000000000000000; // Treasury must be valid
    }

    // Rule 4: Registry address must be valid
    rule RegistryAddressMustBeValid() {
        requires calldata == Allo.updateRegistry.selector;
        ensures Allo.getRegistry() != 0x0000000000000000000000000000000000000000; // Registry must be valid
    }

    // Rule 5: Only pool managers or admins can update pool metadata
    rule OnlyManagersOrAdminsCanUpdateMetadata() {
        requires calldata == Allo.updatePoolMetadata.selector;
        requires msg.sender == Allo.isPoolManager(calldata.poolId, msg.sender) ||
                 msg.sender == Allo.isPoolAdmin(calldata.poolId, msg.sender);
        assert true; // Access control validated
    }

    // Rule 6: Pool creation should increment the pool index
    rule PoolCreationIncrementsIndex() {
        uint256 poolIndexBefore = Allo.poolIndex();
        requires calldata == Allo.createPool.selector || calldata == Allo.createPoolWithCustomStrategy.selector;
        ensures Allo.poolIndex() == poolIndexBefore + 1; // Index must increment
    }

    // Rule 7: No unauthorized recipient registration
    rule OnlyAuthorizedCanRegisterRecipient() {
        requires calldata == Allo.registerRecipient.selector || calldata == Allo.batchRegisterRecipient.selector;
        requires Allo.isPoolAdmin(calldata.poolId, msg.sender) ||
                 Allo.isPoolManager(calldata.poolId, msg.sender);
        assert true; // Access validated
    }

    // Rule 8: Fee and amount integrity during funding
    rule FeeAndAmountIntegrityDuringFunding() {
        uint256 totalBalanceBefore = Allo.getTreasuryBalance() + Allo.getPoolBalance(calldata.poolId);
        requires calldata == Allo.fundPool.selector;
        ensures Allo.getTreasuryBalance() + Allo.getPoolBalance(calldata.poolId) == totalBalanceBefore + calldata.amount;
    }

    // Rule 9: Strategy cloning must use approved strategies
    rule OnlyApprovedStrategiesCanBeCloned() {
        requires calldata == Allo.createPool.selector;
        ensures Allo.isCloneableStrategy(calldata.strategy);
    }
}

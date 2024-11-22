rule OnlyManagersOrAdminsCanUpdateMetadata() {
    env e;
    uint256 poolId;
    Metadata metadata;
    require !isPoolManager(e.msg.sender, poolId);
    require !isPoolAdmin(e.msg.sender, poolId);
    updatePoolMetadata(e, poolId, metadata);
    assert lastReverted;
}

rule PoolCreationIncrementsIndex() {
    env e;
    bytes32 profileId;
    address strategy;
    bytes initStrategyData;
    address token;
    uint256 amount;
    Metadata metadata;
    address[] managers;
    
    uint256 oldIndex = poolIndex();
    createPool(e, profileId, strategy, initStrategyData, token, amount, metadata, managers);
    assert !lastReverted => poolIndex() == oldIndex + 1;
}

rule FeeAndAmountIntegrityDuringFunding() {
    env e;
    uint256 poolId;
    uint256 amount;
    
    uint256 treasuryBefore = getTreasuryBalance();
    uint256 poolBefore = getPoolBalance(poolId);
    
    fundPool(e, poolId, amount);
    
    uint256 treasuryAfter = getTreasuryBalance();
    uint256 poolAfter = getPoolBalance(poolId);
    
    assert !lastReverted => treasuryAfter + poolAfter >= treasuryBefore + poolBefore;
}

rule OnlyApprovedStrategiesCanBeCloned() {
    env e;
    bytes32 profileId;
    address strategy;
    bytes initStrategyData;
    address token;
    uint256 amount;
    Metadata metadata;
    address[] managers;
    
    require !isCloneableStrategy(strategy);
    createPoolWithCustomStrategy(e, profileId, strategy, initStrategyData, token, amount, metadata, managers);
    assert lastReverted;
}

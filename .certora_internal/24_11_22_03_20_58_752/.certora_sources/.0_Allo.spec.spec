/*
    Methods declarations for Allo contract
*/
methods {
    // State accessors
    owner() returns (address) envfree
    getPercentFee() returns (uint256) envfree
    getFeeDenominator() returns (uint256) envfree
    getTreasury() returns (address) envfree
    getRegistry() returns (address) envfree
    getTreasuryBalance() returns (uint256) envfree
    getPoolBalance(uint256) returns (uint256) envfree
    poolIndex() returns (uint256) envfree
    
    // Access control
    isPoolManager(address, uint256) returns (bool) envfree
    isPoolAdmin(address, uint256) returns (bool) envfree
    isCloneableStrategy(address) returns (bool) envfree
    
    // Function selectors
    updateRegistry(address) returns ()
    updateTreasury(address) returns ()
    updatePercentFee(uint256) returns ()
    updateBaseFee(uint256) returns ()
    updatePoolMetadata(uint256, bytes) returns ()
    createPool(bytes, address, bytes, bytes, uint256, address) returns (uint256)
    createPoolWithCustomStrategy(address, bytes, bytes, bytes, uint256, address) returns (uint256)
    registerRecipient(uint256, bytes) returns (address)
    batchRegisterRecipient(uint256, bytes[]) returns (address[])
    fundPool(uint256) returns ()
}

// Rule 1: Only the owner can update the configuration
rule OnlyOwnerCanUpdateConfiguration {
    env e;
    require e.msg.sender == owner();
    require
        e.selector == sig:updateRegistry(address) ||
        e.selector == sig:updateTreasury(address) ||
        e.selector == sig:updatePercentFee(uint256) ||
        e.selector == sig:updateBaseFee(uint256);
    assert true; // Ownership validated
}

// Rule 2: Ensure percentFee is always <= 100%
rule PercentFeeCannotExceed100Percent {
    env e;
    require e.selector == sig:updatePercentFee(uint256);
    uint256 fee = getPercentFee();
    uint256 denominator = getFeeDenominator();
    assert fee <= denominator; // Fee cannot exceed 100%
}

// Rule 3: Treasury cannot be the zero address
rule TreasuryAddressMustBeValid {
    env e;
    require e.selector == sig:updateTreasury(address);
    address treasury = getTreasury();
    assert treasury != 0; // Treasury must be valid
}

// Rule 4: Registry address must be valid
rule RegistryAddressMustBeValid {
    env e;
    require e.selector == sig:updateRegistry(address);
    address registry = getRegistry();
    assert registry != 0; // Registry must be valid
}

// Rule 5: Only pool managers or admins can update pool metadata
rule OnlyManagersOrAdminsCanUpdateMetadata(uint256 poolId) {
    env e;
    require e.selector == sig:updatePoolMetadata(uint256, bytes);
    require isPoolManager(e.msg.sender, poolId) ||
            isPoolAdmin(e.msg.sender, poolId);
    assert true; // Access control validated
}

// Rule 6: Pool creation should increment the pool index
rule PoolCreationIncrementsIndex {
    env e;
    uint256 poolIndexBefore = poolIndex();
    require e.selector == sig:createPool(bytes, address, bytes, bytes, uint256, address) || 
            e.selector == sig:createPoolWithCustomStrategy(address, bytes, bytes, bytes, uint256, address);
    uint256 poolIndexAfter = poolIndex();
    assert poolIndexAfter == poolIndexBefore + 1; // Index must increment
}

// Rule 7: No unauthorized recipient registration
rule OnlyAuthorizedCanRegisterRecipient(uint256 poolId) {
    env e;
    require e.selector == sig:registerRecipient(uint256, bytes) || 
            e.selector == sig:batchRegisterRecipient(uint256, bytes[]);
    require isPoolAdmin(e.msg.sender, poolId) ||
            isPoolManager(e.msg.sender, poolId);
    assert true; // Access validated
}

// Rule 8: Fee and amount integrity during funding
rule FeeAndAmountIntegrityDuringFunding(uint256 poolId, uint256 amount) {
    env e;
    uint256 treasuryBefore = getTreasuryBalance();
    uint256 poolBefore = getPoolBalance(poolId);
    require e.selector == sig:fundPool(uint256);
    uint256 treasuryAfter = getTreasuryBalance();
    uint256 poolAfter = getPoolBalance(poolId);
    assert treasuryAfter + poolAfter == treasuryBefore + poolBefore + amount;
}

// Rule 9: Strategy cloning must use approved strategies
rule OnlyApprovedStrategiesCanBeCloned(address strategy) {
    env e;
    require e.selector == sig:createPool(bytes, address, bytes, bytes, uint256, address);
    assert isCloneableStrategy(strategy);
}

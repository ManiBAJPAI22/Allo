methods {
    // State accessors
    function owner() external returns (address) envfree;
    function getPercentFee() external returns (uint256) envfree;
    function getFeeDenominator() external returns (uint256) envfree;
    function getTreasury() external returns (address) envfree;
    function getRegistry() external returns (address) envfree;
    function getTreasuryBalance() external returns (uint256) envfree optional;
    function getPoolBalance(uint256) external returns (uint256) envfree optional;
    function poolIndex() external returns (uint256) envfree optional;
    
    // Access control
    function isPoolManager(address, uint256) external returns (bool) envfree optional;
    function isPoolAdmin(address, uint256) external returns (bool) envfree optional;
    function isCloneableStrategy(address) external returns (bool) envfree;
}

// Rule 1: Only the owner can update the configuration
rule OnlyOwnerCanUpdateConfiguration(method f) {
    env e;
    calldataarg args;
    address sender = e.msg.sender;
    
    require sender != owner();
    
    if (
        f.selector == updateRegistry(address).selector ||
        f.selector == updateTreasury(address).selector ||
        f.selector == updatePercentFee(uint256).selector ||
        f.selector == updateBaseFee(uint256).selector
    ) {
        f@withrevert(e, args);
        assert lastReverted;
    }
}

// Rule 2: Ensure percentFee is always <= 100%
rule PercentFeeCannotExceed100Percent() {
    env e;
    calldataarg args;
    
    uint256 feeBefore = getPercentFee();
    updatePercentFee@withrevert(e, args);
    uint256 feeAfter = getPercentFee();
    
    assert !lastReverted => feeAfter <= getFeeDenominator();
}

// Rule 3: Treasury cannot be the zero address
rule TreasuryAddressMustBeValid() {
    env e;
    calldataarg args;
    
    updateTreasury@withrevert(e, args);
    
    assert !lastReverted => getTreasury() != 0;
}

// Rule 4: Registry address must be valid
rule RegistryAddressMustBeValid() {
    env e;
    calldataarg args;
    
    updateRegistry@withrevert(e, args);
    
    assert !lastReverted => getRegistry() != 0;
}

// Rule 5: Only pool managers or admins can update pool metadata
rule OnlyManagersOrAdminsCanUpdateMetadata(uint256 poolId) {
    env e;
    calldataarg args;
    address sender = e.msg.sender;
    
    require !isPoolManager(sender, poolId);
    require !isPoolAdmin(sender, poolId);
    
    updatePoolMetadata@withrevert(e, poolId, args);
    assert lastReverted;
}

// Rule 6: Pool creation should increment the pool index
rule PoolCreationIncrementsIndex() {
    env e;
    calldataarg args;
    
    uint256 indexBefore = poolIndex();
    createPool@withrevert(e, args) returns (uint256 newIndex);
    
    assert !lastReverted => poolIndex() == indexBefore + 1;
}

// Rule 7: No unauthorized recipient registration
rule OnlyAuthorizedCanRegisterRecipient(uint256 poolId) {
    env e;
    calldataarg args;
    address sender = e.msg.sender;
    
    require !isPoolAdmin(sender, poolId);
    require !isPoolManager(sender, poolId);
    
    registerRecipient@withrevert(e, poolId, args);
    assert lastReverted;
}

// Rule 8: Fee and amount integrity during funding
rule FeeAndAmountIntegrityDuringFunding(uint256 poolId) {
    env e;
    calldataarg args;
    
    uint256 treasuryBefore = getTreasuryBalance();
    uint256 poolBefore = getPoolBalance(poolId);
    
    fundPool@withrevert(e, args);
    
    uint256 treasuryAfter = getTreasuryBalance();
    uint256 poolAfter = getPoolBalance(poolId);
    
    assert !lastReverted => treasuryAfter + poolAfter >= treasuryBefore + poolBefore;
}

// Rule 9: Strategy cloning must use approved strategies
rule OnlyApprovedStrategiesCanBeCloned() {
    env e;
    calldataarg args;
    address strategy;
    
    require !isCloneableStrategy(strategy);
    createPoolWithCustomStrategy@withrevert(e, strategy, args);
    
    assert lastReverted;
}
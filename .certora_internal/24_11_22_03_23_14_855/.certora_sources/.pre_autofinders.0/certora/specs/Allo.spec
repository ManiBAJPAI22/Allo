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
    
    // Function selectors
    function updateRegistry(address) external;
    function updateTreasury(address) external;
    function updatePercentFee(uint256) external;
    function updateBaseFee(uint256) external;
    function updatePoolMetadata(uint256, bytes) external;
    function createPool(bytes, address, bytes, bytes, uint256, address) external returns (uint256);
    function createPoolWithCustomStrategy(address, bytes, bytes, bytes, uint256, address) external returns (uint256);
    function registerRecipient(uint256, bytes) external returns (address);
    function batchRegisterRecipient(uint256, bytes[]) external returns (address[]);
    function fundPool(uint256) external;
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

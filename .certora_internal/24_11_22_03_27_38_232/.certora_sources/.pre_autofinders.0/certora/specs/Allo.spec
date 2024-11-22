methods {
    // State accessors
    function owner() external returns (address) envfree;
    function getPercentFee() external returns (uint256) envfree;
    function getFeeDenominator() external returns (uint256) envfree;
    function getTreasury() external returns (address) envfree;
    function getRegistry() external returns (address) envfree;
    function getTreasuryBalance() external returns (uint256) envfree;
    function getPoolBalance(uint256) external returns (uint256) envfree;
    function poolIndex() external returns (uint256) envfree;
    
    // Access control
    function isPoolManager(address, uint256) external returns (bool) envfree;
    function isPoolAdmin(address, uint256) external returns (bool) envfree;
    function isCloneableStrategy(address) external returns (bool) envfree;
    
    // Function implementations to verify
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

definition isConfigFunction(method f) returns bool = 
    f.selector == sig:updateRegistry(address).selector ||
    f.selector == sig:updateTreasury(address).selector ||
    f.selector == sig:updatePercentFee(uint256).selector ||
    f.selector == sig:updateBaseFee(uint256).selector;

rule OnlyOwnerCanUpdateConfiguration(method f) {
    env e;
    require isConfigFunction(f);
    require e.msg.sender != owner();
    f@withrevert(e);
    assert lastReverted;
}

rule PercentFeeCannotExceed100Percent() {
    env e;
    uint256 newFee;
    updatePercentFee@withrevert(e, newFee);
    assert !lastReverted => getPercentFee() <= getFeeDenominator();
}

rule TreasuryAddressMustBeValid() {
    env e;
    address newTreasury;
    updateTreasury@withrevert(e, newTreasury);
    assert !lastReverted => getTreasury() != 0;
}

rule RegistryAddressMustBeValid() {
    env e;
    address newRegistry;
    updateRegistry@withrevert(e, newRegistry);
    assert !lastReverted => getRegistry() != 0;
}

rule OnlyManagersOrAdminsCanUpdateMetadata() {
    env e;
    uint256 poolId;
    bytes metadata;
    require !isPoolManager(e.msg.sender, poolId);
    require !isPoolAdmin(e.msg.sender, poolId);
    updatePoolMetadata@withrevert(e, poolId, metadata);
    assert lastReverted;
}

rule PoolCreationIncrementsIndex() {
    env e;
    bytes metadata;
    address strategy;
    bytes data;
    bytes initData;
    uint256 id;
    address manager;
    
    uint256 oldIndex = poolIndex();
    createPool@withrevert(e, metadata, strategy, data, initData, id, manager);
    assert !lastReverted => poolIndex() == oldIndex + 1;
}

rule OnlyAuthorizedCanRegisterRecipient() {
    env e;
    uint256 poolId;
    bytes data;
    require !isPoolManager(e.msg.sender, poolId);
    require !isPoolAdmin(e.msg.sender, poolId);
    registerRecipient@withrevert(e, poolId, data);
    assert lastReverted;
}

rule FeeAndAmountIntegrityDuringFunding() {
    env e;
    uint256 poolId;
    uint256 amount;
    
    uint256 treasuryBefore = getTreasuryBalance();
    uint256 poolBefore = getPoolBalance(poolId);
    
    fundPool@withrevert(e, amount);
    
    uint256 treasuryAfter = getTreasuryBalance();
    uint256 poolAfter = getPoolBalance(poolId);
    
    assert !lastReverted => treasuryAfter + poolAfter >= treasuryBefore + poolBefore;
}

rule OnlyApprovedStrategiesCanBeCloned() {
    env e;
    address strategy;
    bytes metadata;
    bytes data;
    bytes initData;
    uint256 id;
    address manager;
    
    require !isCloneableStrategy(strategy);
    createPoolWithCustomStrategy@withrevert(e, strategy, metadata, data, initData, id, manager);
    assert lastReverted;
}
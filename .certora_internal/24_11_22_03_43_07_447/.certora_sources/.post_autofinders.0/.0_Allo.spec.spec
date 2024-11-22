// Define the methods you want to verify
methods {
    function getPercentFee() external returns (uint256) envfree;
    function getFeeDenominator() external returns (uint256) envfree;
    function poolIndex() external returns (uint256) envfree optional;
    function updatePoolMetadata(uint256, bytes) external envfree optional;
    function createPool(bytes32, address, bytes, address, uint256, bytes, address[]) external returns (uint256) envfree optional;
    function fundPool(uint256, uint256) external envfree optional;
    function isPoolManager(address, uint256) external returns (bool) envfree optional;
}

// Define the rules to verify
rule PercentFeeCannotExceed100Percent {
    env e;
    uint256 fee;
    address ZERO_ADDRESS = 0x0000000000000000000000000000000000000000; // Inline definition
    require e.msg.sender != ZERO_ADDRESS; // Replacing address(0) with ZERO_ADDRESS
    assert getPercentFee() <= getFeeDenominator();
}

rule PoolIndexIncrementsAfterCreation {
    env e;
    bytes32 profileId;
    address strategy;
    bytes initStrategyData;
    address token;
    uint256 amount;
    bytes metadata;
    address[] managers;

    uint256 oldIndex = poolIndex();
    createPool(e, profileId, strategy, initStrategyData, token, amount, metadata, managers);
    assert poolIndex() == oldIndex + 1;
}

rule OnlyManagersCanUpdateMetadata {
    env e;
    uint256 poolId;
    bytes metadata;
    address sender = e.msg.sender;

    require !isPoolManager(sender, poolId);
    updatePoolMetadata@withrevert(e, poolId, metadata);
    assert lastReverted;
}

rule PoolManagersCanUpdateMetadata {
    env e;
    uint256 poolId;
    bytes metadata;
    address sender = e.msg.sender;

    require isPoolManager(sender, poolId);
    updatePoolMetadata(e, poolId, metadata);
    assert !lastReverted;
}

rule ZeroAddressCannotCreatePool {
    env e;
    bytes32 profileId;
    address strategy;
    bytes initStrategyData;
    address token = 0x0000000000000000000000000000000000000000; // Zero address for token
    uint256 amount;
    bytes metadata;
    address[] managers;

    createPool@withrevert(e, profileId, strategy, initStrategyData, token, amount, metadata, managers);
    assert lastReverted;
}

rule PoolCreationInitializesStrategy {
    env e;
    bytes32 profileId;
    address strategy;
    bytes initStrategyData;
    address token;
    uint256 amount;
    bytes metadata;
    address[] managers;

    uint256 poolId = createPool(e, profileId, strategy, initStrategyData, token, amount, metadata, managers);
    assert poolId > 0;
}

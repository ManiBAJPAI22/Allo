methods {
    // State accessors
    function getPercentFee() external returns (uint256) envfree;
    function getFeeDenominator() external returns (uint256) envfree;
    function getTreasury() external returns (address) envfree;
    function poolIndex() external returns (uint256) envfree optional;

    // Access control
    function isPoolManager(address, uint256) external returns (bool) envfree optional;

    // Pool management
    function updatePoolMetadata(uint256, bytes) external envfree optional;
    function createPool(bytes32, address, bytes, address, uint256, bytes, address[]) external returns (uint256) envfree optional;
    function fundPool(uint256, uint256) external envfree optional;
}

rules {
    // Rule to ensure the fee percentage does not exceed 100%
    rule PercentFeeCannotExceed100Percent() {
        env e;
        uint256 newFee;
        updatePercentFee@withrevert(e, newFee);
        assert !lastReverted => getPercentFee() <= getFeeDenominator();
    }

    // Rule to ensure pool creation increments the pool index
    rule PoolCreationIncrementsIndex() {
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
        assert !lastReverted => poolIndex() == oldIndex + 1;
    }

    // Rule to ensure only pool managers can update pool metadata
    rule OnlyManagersCanUpdateMetadata() {
        env e;
        uint256 poolId;
        bytes metadata;

        require !isPoolManager(e.msg.sender, poolId);
        updatePoolMetadata@withrevert(e, poolId, metadata);
        assert lastReverted;
    }
}

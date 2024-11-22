// Define the methods you want to verify
methods {
    function getPercentFee() external returns (uint256) envfree;
    function getFeeDenominator() external returns (uint256) envfree;
    function poolIndex() external returns (uint256) envfree optional;
    function updatePoolMetadata(uint256, bytes) external envfree optional;
    function createPool(bytes32, address, bytes, address, uint256, bytes, address[]) external returns (uint256) envfree optional;
}

// Constants
const address ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;

// Define the rules to verify
rule PercentFeeCannotExceed100Percent {
    env e;
    uint256 fee;
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

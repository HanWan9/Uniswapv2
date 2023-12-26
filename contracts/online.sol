/**
 * submitted for verification at Etherscan.io on 2020-09-30
 */

// File: @uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol
pragma solidity ^0.5.6;

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0, 
        address indexed token1, 
        address pair, 
        uint256
    );

    function feeTo() external view returns (address);
    
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) 
        external 
        view 
        returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB) 
        external 
        returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}
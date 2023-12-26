pragma solidity =0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

// uniswap 工厂合约
contract UniswapV2Factory is IUniswapV2Factory {
    address public feeTo; // 收取手续费的地址
    address public feeToSetter; // 设置收取手续费的地址
    // 交易对地址映射,地址=>(地址=>地址)
    mapping(address => mapping(address => address)) public getPair;
    // 交易对地址数组
    address[] public allPairs;
    // 交易对创建事件, token0, token1, pair地址, 交易对数组长度: allPairs.length
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    // 构造函数, 收税开关权限控制
    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    // 查询配对数组长度的方法
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    /**
     * 
     * @param tokenA 
     * @param tokenB 
     * @return pair 配对地址
     * @dev 创建配对合约, 传入两个token地址, 通过排序后的地址作为key, 查询配对地址, 如果配对地址不为0, 则直接返回, 否则创建配对合约, 并初始化配对合约
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // 传入的两个token地址不能相同
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        // 将token地址排序, 小的在前, 大的在后
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // token0地址不能为0地址
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        // 通过排序后的token0, token1地址作为key, 查询配对地址,判断是否存在
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        // 给bytecode赋值, 通过bytecode创建合约，bytecode是合约的二进制代码，由于是不定长度的字节，所以需要加上memory
        // 值的获取是通过type(UniswapV2Pair).creationCode;获取的，与UniswaV2Pair合约的构造函数对应
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        // 通过keccak256哈希算法, 传入token0, token1地址, 打包后创建hash，生成salt
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        // 内联汇编
        // solium-disable-next-line
        // line 51-56 完成了配对合约的部署以及初始化
        assembly {
            // 通过create2创建合约, 并且加盐，返回地址到pair变量
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        // 调用pair地址的合约中的"initialize"方法, 传入token0, token1地址
        IUniswapV2Pair(pair).initialize(token0, token1);

        // 将配对地址存入mapping中, token0=>token1=pair地址
        getPair[token0][token1] = pair;
        // 将配对地址存入mapping中, token1=>token0=pair地址
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        // 将配对地址存入配对数组中
        allPairs.push(pair);
        // 触发配对创建成功事件
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /**
     * @dev 设置收税地址
     * @param _feeTo 收税地址
     */
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    /**
     * @dev 设置收税开关权限控制地址
     * @param _feeToSetter 收税开关权限控制地址
     */
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
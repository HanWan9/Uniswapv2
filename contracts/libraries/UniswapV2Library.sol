pragma solidity >=0.5.0;

import '../interfaces/IUniswapV2Pair.sol';

import "./SafeMath.sol";

library UniswapV2Library {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        // 确认tokenA, tokenB地址不相同
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        // 排序token地址
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // 确认token地址不能为0地址
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    /**
     * @dev 获取pair合约地址
     * @notice 计算配对的CREATE2地址，而不进行任何外部调用
     * @param factory 工厂地址
     * @param tokenA tokenA地址
     * @param tokenB tokenB地址
     * @return pair pair合约地址
     */
    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        // 排毒token地址
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        // 根据排序的token地址计算create2的pair地址
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)), // 盐
                // pair合约bytecode的keccak256哈希值
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            ))));
    }

    /**
     * @dev 获取储备
     * @notice 提取并排序配对的储备
     * @param factory 工厂地址
     * @param tokenA tokenA地址
     * @param tokenB tokenB地址
     * @return reserveA 储备量A
     * @return reserveB 储备量B
     */
    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        // 排序token地址
        (address token0,) = sortTokens(tokenA, tokenB);
        // 通过排序后的地址和工厂合约地址获取到pair合约地址，并从pair合约中获取储备量0,1，最后是时间戳
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        // 根据输入的token顺序返回储备量
        (reserveA, reserveB) = tokenA == token0 
            ? (reserve0, reserve1) 
            : (reserve1, reserve0);
    }

    /**
     * @dev 对价计算
     * @notice 给定一定数量的资产和货币对储备金，则返回等值的其他资产
     * @param amountA 数额A
     * @param reserveA 储备量A
     * @param reserveB 储备量B
     * @return amounts 数额B
     */
    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint256 amountA, 
        uint256 reserveA, 
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        // 确认数额A > 0
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        // 确认储备量A, 储备量B > 0
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        // 数额B = 数额A * 储备量B / 储备量A
        amountB = amountA.mul(reserveB) / reserveA;
    }

    /**
     * @dev 获取单个输出数额
     * @notice 给定一项资产的输入量和配对的储备，返回另一项资产的最大输出量
     * @param amountIn 输入数额
     * @param reserveIn 储备量In
     * @param reserveOut 储备量Out
     * @return amountOut 输出数额
     */
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn, 
        uint256 reserveIn, 
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        // 确认输入数额 > 0
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        // 确认储备量In, 储备量Out > 0
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        // 税后输入数额 = 输入数额 * 997
        uint256 amountInWithFee = amountIn.mul(997);
        // 分子 = 税后输入数额 * 储备量Out
        uint256 numerator = amountInWithFee.mul(reserveOut);
        // 分母 = 储备量In * 1000 + 税后输入数额
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        // 输出数额 = 分子 / 分母
        amountOut = numerator / denominator;
    }

    /**
     * @dev 获取单个输出数额（实际为输入量）
     * @notice 给定一项资产的输出量和配对的储备，返回另一项资产的所需输入量
     * @param amountOut 输出数额
     * @param reserveIn 储备量In
     * @param reserveOut 储备量Out
     * @return amountIn 输入数额
     */
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut, 
        uint256 reserveIn, 
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        // 确认输出数额 > 0
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        // 确认储备量In, 储备量Out > 0
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        // 分子 = 储备量In * 储备量Out * 1000
        uint256 numerator = reserveIn.mul(amountOut).mul(1000);
        // 分母 = （储备量Out - 输出数额）* 997
        uint256 denominator = reserveOut.sub(amountOut).mul(997);
        // 输入数额 = （分子 / 分母）+ 1
        // Q: 为什么要加1？
        // A: 因为分子 / 分母的结果是向下取整的，所以需要加1
        amountIn = (numerator / denominator).add(1);
    }

    /**
     * @dev 获取输出数额
     * @notice 对任意数量的对执行链接的getAmountOut计算
     * @param factory 工厂合约地址
     * @param amountIn 输入数额
     * @param path 路径数组
     * @return amounts 输出数额数组
     */
    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        // 确认路径长度 >= 2
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        // 初始化数额数组
        amounts = new uint256[](path.length);
        // 数额数组[0] = 输入数额
        amounts[0] = amountIn;
        // 遍历路径数组，path长度-1
        for (uint256 i; i < path.length - 1; i++) {
            // （储备量In，储备量Out）= 获取储备（当前路径地址，下一个路径地址）
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            // 下一个数额 = 获取输出数额（当前数额，储备量In，储备量Out）
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /**
     * @dev 获取输入数额
     * @notice 对任意数量的对执行链接的getAmountIn计算
     * @param factory 工厂合约地址
     * @param amountOut 输出数额
     * @param path 路径数组
     * @return amounts[] 输入数额数组
     */
    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path) internal view returns (uint256[] memory amounts) {
        // 确认路径长度 >= 2
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        // 初始化数额数组
        amounts = new uint256[](path.length);
        // 数额数组[最后一个] = 输出数额
        amounts[amounts.length - 1] = amountOut;
        // 从倒数第二个元素倒序遍历路径数组
        for (uint256 i = path.length - 1; i > 0; i--) {
            // (储备量In，储备量Out) = 获取储备（上一个路径地址，当前路径地址）
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                factory, 
                path[i - 1], 
                path[i]
            );
            // 上一个数额 = 获取输入数额（当前数额，储备量In，储备量Out）
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
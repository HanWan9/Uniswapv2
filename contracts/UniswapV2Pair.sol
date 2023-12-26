pragma solidity =0.5.16;

// 接口合约
import './interfaces/IUniswapV2Pair.sol';
// ERC20合约
import './UniswapV2ERC20.sol';
// 安全数学运算库
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
// ERC20接口合约
import './interfaces/IERC20.sol';
// 工厂合约的接口合约
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

// Uniswap交易对合约
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    // 定义库
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    // 定义最小流动性 = 1000；
    // 白皮书3.4章节，定义为10**-15,10**-18相当于一个wei，10**-15相当于一个ether,有助于增加攻击成本
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    // SELECTOR 常量值为'transfer(address,uint256)'字符串哈希值的前四个字节（8位，16进制数字）
    bytes4 private constant SELECTOR = bytes4(
        keccak256(bytes('transfer(address,uint256)'))
    );

    address public factory; // 工厂合约地址
    address public token0; // token0地址
    address public token1; // token1地址

    uint112 private reserve0;           // 储备量0，uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // 储备量1，uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // 更新储备量的最后时间戳，uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast; // 价格累最后积量0，用于计算价格
    uint public price1CumulativeLast; // 价格累最后积量1，用于计算价格
    
    uint public kLast; // k值，在最近一次流动性时间后，储备量0 * 储备量1，用于计算流动性
    uint private unlocked = 1; // 锁定标志位，用于修饰符lock

    // 事件:铸造
    event Mint(address indexed sender, uint amount0, uint amount1);
    // 事件:销毁
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    /**
     * @dev 事件:交换
     * @param sender 发送者
     * @param amount0In 输入金额0
     * @param amount1In 输入金额1
     * @param amount0Out 输出金额0
     * @param amount1Out 输出金额1
     * @param to to地址
     */
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    // 事件:同步； 储备量0，储备量1
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() public {
        // factory地址为合约部署者
        factory = msg.sender;
    }

    /**
     * @dev 初始化方法，部署时由工厂合约调用一次
     * @param _token0 token0地址
     * @param _token1 token1地址 
     */
    function initialize(address _token0, address _token1) external {
        // 确保只能由工厂合约调用
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // 修饰符，锁定运行，防止重入攻击
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /**
     * @dev 获取储备量
     * @return _reserve0 储备量0
     * @return _reserve1 储备量1
     * @return _blockTimestampLast 最后更新时间戳 
     */
    function getReserves() 
        public 
        view 
        returns (
            uint112 _reserve0, 
            uint112 _reserve1, 
            uint32 _blockTimestampLast
            ) 
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /**
     * @dev 私有安全发送方法
     * @param token token地址
     * @param to to地址
     * @param value 数量
     */
    function _safeTransfer(
        address token, 
        address to, 
        uint value
    ) private {
        // 调用token合约地址的低级transfer方法
        // solium-disable-next-line
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(SELECTOR, to, value)
        );
        // 确认返回值为true，并且返回的data长度为0或者data解码后为true
        require(
            success && (data.length == 0 || abi.decode(data, (bool))), 
            'UniswapV2: TRANSFER_FAILED'
        );
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint balance0, 
        uint balance1, 
        uint112 _reserve0, 
        uint112 _reserve1
    ) private {
        // 确认余额0和余额1不超过uint112的最大值
        require(
            balance0 <= uint112(-1) && balance1 <= uint112(-1), 
            'UniswapV2: OVERFLOW'
        );
        // 获取当前区块时间戳, 将时间戳转换为uint32类型
        // solium-disable-next-line
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        // 计算时间流逝
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        // 如果时间流逝大于0，并且储备量0和储备量1不为0
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            // 以下两个值将在价格预言机种进行使用，合约只进行记录，不使用
            // 计算价格0最后累计 += (储备量1 * 2**112 / 储备量0) * 时间流逝
            // solium-disable-next-line
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            // 计算价格1最后累计 += (储备量0 * 2**112 / 储备量1) * 时间流逝
            // solium-disable-next-line
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        // 将当前余额0, 余额1, 时间戳赋值给储备量0, 储备量1, 最后更新时间戳
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        // 触发同步事件
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    /**
     * @dev 如果收费，铸造流动性相当于sqrt（k）增长的1/6
     * @param _reserve0 储备量0
     * @param _reserve1 储备量1
     * @return feeOn 收费开关
     */
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        // 获取工厂合约的feeTo变量值
        address feeTo = IUniswapV2Factory(factory).feeTo();
        // 如果feeTo不为0地址，则收费开关为true
        feeOn = feeTo != address(0);
        // 定义kLast变量，为k值。将当前的k值赋值给k值的临时变量
        uint _kLast = kLast; // gas savings
        // 如果收费开关为true，并且kLast不为0
        if (feeOn) {
            if (_kLast != 0) {
                // 计算(储备量0 * 储备量1)的平方根
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                // 计算_kLast的平方根
                uint rootKLast = Math.sqrt(_kLast);
                // rootK > rootKLast
                if (rootK > rootKLast) {
                    // 分子 = erc20总量 * (rootK - rootKLast)
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    // 分母 = rootK * 5 + rootKLast
                    uint denominator = rootK.mul(5).add(rootKLast);
                    // 流行性 = 分子 / 分母
                    uint liquidity = numerator / denominator;
                    // 如果流动性大于0，则铸造流动性给feeTo地址
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    /**
     * @dev 铸造方法
     * @param to to地址
     * @return liquidity 流动性
     * @notice 应该从执行重要安全检查的合约中调用此低级功能。
     */
    function mint(address to) external lock returns (uint liquidity) {
        // 获取储备量0, 储备量1
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        // 获取当前合约地址在token0, token1合约中的余额
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        // amount0 = 当前合约地址在token0合约中的余额 - 储备量0
        uint amount0 = balance0.sub(_reserve0);
        // amount1 = 当前合约地址在token1合约中的余额 - 储备量1
        uint amount1 = balance1.sub(_reserve1);

        // 返回铸造费开关
        bool feeOn = _mintFee(_reserve0, _reserve1);
        // 获取totalSupply，必须在此处定义，因为totalSupply可以在_mintFee中更新
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        // 如果totalSupply为0
        if (_totalSupply == 0) {
            // 流动性 = sqrt(amount0 * amount1) - 最小流动性1000
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            // 在总量为0的初始状态，永久锁定最低流动性
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            // 流动性 = min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1)
            liquidity = Math.min(
                amount0.mul(_totalSupply) / _reserve0, 
                amount1.mul(_totalSupply) / _reserve1
            );
        }
        // 确认流动性 > 0
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        // 铸造流动性给to地址
        _mint(to, liquidity);

        // 更新储备量
        _update(balance0, balance1, _reserve0, _reserve1);
        // 如果铸造费开关为true，k值 = 储备0 * 储备1
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        // 触发铸造事件
        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     * @dev 销毁方法
     * @param to to地址
     * @return amount0 token0对应的可以取出的数值
     * @return amount1 token1对应的可以取出的数值
     * @notice 应该从执行重要安全检查的合约中调用此低级功能
     */
    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) 
        external 
        lock 
        returns (uint amount0, uint amount1) 
    {
        // 获取储备量0, 储备量1
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        // 带入变量，赋予临时变量，为节省gas
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        // 获取当前合约地址在token0, token1合约中的余额
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        // 从当前合约的balanceOf映射中获取当前合约自身的流动性数量
        // 此处和mint function不同，铸造时是在铸造结束才会取得流动性的值，此出为一开始获取流动性的值
        // 此处获取的是当前合约的流动性余额，为通过路由合约发过来的流动性
        uint liquidity = balanceOf[address(this)];

        // 返回铸造费开关
        bool feeOn = _mintFee(_reserve0, _reserve1);
        // 获取totalSupply，必须在此处定义，因为totalSupply可以在mintFee中更新
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        // amount0 = 流动性数量 * 余额0 / totalSupply 使用余额确保按比例分配
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        // amount1 = 流动性数量 * 余额1 / totalSupply 使用余额确保按比例分配
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        // 确认amount0和amount1都大于0
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        // 销毁当前合约内的流动性数量
        _burn(address(this), liquidity);
        // 将amount0数量的_token0发送给to地址
        _safeTransfer(_token0, to, amount0);
        // 将amount1数量的_token1发送给to地址
        _safeTransfer(_token1, to, amount1);
        // 更新当前余额
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        // 更新储备量
        _update(balance0, balance1, _reserve0, _reserve1);
        // 如果铸造费开关为true，k值 = 储备0 * 储备1
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        // 触发销毁事件
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /**
     * @dev 交换方法
     * @param amount0Out 输出数额0
     * @param amount1Out 输出数额1
     * @param to to地址
     * @param data 用于回调的数据
     * @notice 应该从执行重要安全检查的合约中调用此低级功能
     */
    // this low-level function should be called from a contract which performs important safety checks
    function swap(
        uint256 amount0Out, 
        uint256 amount1Out, 
        address to, 
        bytes calldata data
    ) external lock {
        // 确认amount0Out和amount1Out都大于0
        require(
            amount0Out > 0 || amount1Out > 0, 
            'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT'
        );
        // 获取储备量0, 储备量1
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        // 确认输出数量0，1都小于储备量0和储备量1
        require(
            amount0Out < _reserve0 && amount1Out < _reserve1, 
            'UniswapV2: INSUFFICIENT_LIQUIDITY'
        );

        // 初始化变量
        uint256 balance0;
        uint256 balance1;
        {// 合约中可以通过花括号的方法来标记作用域，这样可以避免堆栈太深的错误
            // scope for _token{0,1}, avoids stack too deep errors
            // 标记{_token0, _token1}的作用域，防止堆栈太深超额的错误
            address _token0 = token0;
            address _token1 = token1;
            // 确认to地址不为_token0和_token1
            require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
            // 如果amount0Out大于0，则将amount0Out数量的_token0安全发送给to地址
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            // 如果amount1Out大于0，则将amount1Out数量的_token1安全发送给to地址
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            // 如果data长度大于0，则调用to地址的合约中的uniswapV2Call方法
            // 下面这一步完成了闪电贷的功能
            if (data.length > 0) 
                IUniswapV2Callee(to).uniswapV2Call(
                    msg.sender, 
                    amount0Out, 
                    amount1Out, 
                    data
                );
            // 余额0,1 = 当前合约地址在token0, token1合约中的余额
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        // 如果余额0 > 储备量0 - amount0Out，则amount0In = 余额0 - (储备量0 - amount0Out)，否则amount0In = 0
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        // 如果余额1 > 储备量1 - amount1Out，则amount1In = 余额1 - (储备量1 - amount1Out)，否则amount1In = 0
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        // 确认amount0In或amount1In 大于 0
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            // 标记reserve{0,1}Adjusted的作用域，防止堆栈太深超额的错误
            // 调整后的余额0 = 余额0 * 1000 - amount0In * 3
            uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            // 调整后的余额1 = 余额1 * 1000 - amount1In * 3
            uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
            // 确认调整后的余额0 * 调整后的余额1 >= 储备量0 * 储备量1 * 1000^2
            // 目的：来计算之前的路由合约收过税了
            require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
        }

        // 更新储备量
        _update(balance0, balance1, _reserve0, _reserve1);
        // 触发交换事件
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /**
     * @dev 强制平衡以匹配储备量
     * @param to to地址
     * @notice 白皮书3.2.2 sync()和skim()
     */
    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        // 将当前合约地址在token0, token1合约中的余额 - 储备量0, 储备量1，安全发送到to地址
        _safeTransfer(
            _token0, 
            to, 
            IERC20(_token0).balanceOf(address(this)).sub(reserve0)
        );
        _safeTransfer(
            _token1, 
            to, 
            IERC20(_token1).balanceOf(address(this)).sub(reserve1)
        );
    }

    /**
     * @dev 强制准备金与余额匹配
     * @notice 白皮书3.2.2 sync()和skim()
     */
    // force reserves to match balances
    function sync() external lock {
        _update(
            IERC20(token0).balanceOf(address(this)), 
            IERC20(token1).balanceOf(address(this)), 
            reserve0, 
            reserve1
        );
    }
}
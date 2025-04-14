// https://blog.csdn.net/weixin_39430411/article/details/108965855

pragma solidity =0.5.16;

import './interfaces/ICherryPair.sol';
import './CherryERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/ICherryFactory.sol';
import './interfaces/ICherryCallee.sol';

// 配对合约
contract CherryPair is ICherryPair, CherryERC20 {

    // 引入安全数学运算库
    using SafeMath  for uint;
    // 引入一种处理二进制固定点数的库
    using UQ112x112 for uint224;

    // 定义了最小流动性。它是最小数值1的1000倍，用来在提供初始流动性时燃烧掉
    uint public constant MINIMUM_LIQUIDITY = 10 ** 3;

    // 用来计算标准ERC20合约中转移代币函数transfer的函数选择器。虽然标准的ERC20合约在转移代币后返回一个成功值，但有些不标准的并没有返回值。
    // 在这个合约里统一做了处理，并使用了较低级的call函数代替正常的合约调用。函数选择器用于call函数调用中
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    // 工厂合约地址
    address public factory;

    // token0代币
    address public token0;
    // token1代币
    address public token1;

    // 输入的token0代币的数量
    uint112 private reserve0;
    // 输入的token1代币的数量
    uint112 private reserve1;
    // 交易时的区块时间
    uint32  private blockTimestampLast;

    // 记录交易对中两种价格的累计值
    uint public price0CumulativeLast;
    // 记录交易对中两种价格的累计值
    uint public price1CumulativeLast;

    // 恒定乘积中k的值  kLast = reserve0 * reserve1
    uint public kLast;

    uint private unlocked = 1;

    // 这段代码是用来防重入攻击的，在modifier（函数修饰器）中，_;代表执行被修饰的函数体。
    // 所以这里的逻辑很好理解，当函数（外部接口）被外部调用时，unlocked设置为0，函数执行完之后才会重新设置为1。
    // 在未执行完之前，这时如果重入该函数，lock修饰器仍然会起作用。这时unlocked仍然为0，无法通过修饰器中的require检查，整个交易会被重置。
    // 当然这里也可以不用0和1，也可以使用布尔类型true和false。
    modifier lock() {
        // 必须要求unlocked为1
        require(unlocked == 1, 'Cherry: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // 获取到输入的token0的reserve0，token1的reserve1，以及最后交易的区块时间
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // 安全转账方法
    // 使用call函数进行代币合约transfer的调用（使用了函数选择器）。
    // 注意，它检查了返回值（首先必须调用成功，然后无返回值或者返回值为true）。
    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Cherry: TRANSFER_FAILED');
    }

    // 增发事件
    event Mint(address indexed sender, uint amount0, uint amount1);
    // 销毁事件
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    // 两个币之间的兑换事件
    event Swap(
        address indexed sender, // sender地址
        uint amount0In, // 输入的token0数量
        uint amount1In, // 输入的token1数量
        uint amount0Out, // 输出的token0数量
        uint amount1Out, // 输出的token1数量
        address indexed to // to地址
    );

    // 同步事件
    event Sync(uint112 reserve0, uint112 reserve1);

    // 构造函数
    constructor() public {
        // 工厂合约的地址
        factory = msg.sender;
    }

    // 初始化
    function initialize(address _token0, address _token1) external {
        // 必须要求合约调用者是工厂合约地址
        require(msg.sender == factory, 'Cherry: FORBIDDEN');
        // 充分的检查
        token0 = _token0;
        token1 = _token1;
    }

    // 更新储备量，并在每个区块第一次调用时，更新价格累加器price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        // 要求balance0和balance1要在指定的范围内
        require(balance0 <= uint112(- 1) && balance1 <= uint112(- 1), 'Cherry: OVERFLOW');
        // 时间戳换算
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        // 已经过去的时间 = 当前时间 - 上一个时间
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        // 如果已经过去的时间 大于 0，并且输入的_reserve0和_reserve1都不为0
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // 价格累加器
            // 永远不要溢出，并且希望+溢出
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        // reserve0换算
        reserve0 = uint112(balance0);
        // reserve1换算
        reserve1 = uint112(balance1);
        // 上一个时间戳 就为 当前时间戳
        blockTimestampLast = blockTimestamp;

        // 监听同步的事件
        emit Sync(reserve0, reserve1);
    }

    // 如果fee的开关是开的，手续费的1/6给到feeTo地址，剩下的5/6才分发给流动性提供者。
    // 如果每次用户交易都计算并发送手续费，无疑会增加用户的gas。
    // 为了避免这种情况的出现，我们将开发团队手续费累积起来，在改变流动性时才发送。
    // _mintFee函数就是计算并发送开发团队手续费的。
    // 函数的参数为交易对中保存的恒定乘积中的两种代币的数值
    /*
        注意到该语句里面还嵌套一个if(_kLast != 0)条件语句，这是为什么呢？

        要理解这一点，需要看if(feeOn)的else语句，这里判定如果记录的旧的某时刻的乘积值不为0，则设置为0。
        这么做的目的是因为手续费开关是可以重复打开关闭的。从后面的mint或者burn函数中，我们可以看到只有手续费打开才会更新这个kLast的值，关闭后是不会更新的。
        假定打开后再关闭，此时如果不设置kLast为0，那它就是一个无法更新的旧值。然后我们再打开开关，此时kLast是一个很久前的旧值，而不是最近更新的值，而使用旧值会将开关再次打开前的的数据也计算进去（而不是从开关打开的那一时刻开始计算）。

        同样这里因为在手续费关闭时将kLast设置为0，if(_kLast != 0)这个条件语句就很好理解了，因为此时代表开关打开，但是最近一次还未更新（开关打开后更新发生在_mint函数之后，此时值为0），所以不能计算。
        开关打开后只有先更新一次最新的kLast值有了比较才能继续计算。

        从这里可以看出，开关打开后的第一次流动性操作只是建立了一个过去时刻的快照值kLast，第二次流动性操作才会有新的快照值，才能使用上面的公式计算手续费。

        这里有人可能会有疑惑，我第一次流动性操作和第一次流动性操作的恒定乘积中K的值从代码中是无法看到变化（_mintFee函数发生在更新reserve0和reserve1之前），它们的差额不是0么，哪有什么手续费。
        是的，如果只是连续的两次流动性操作，k2是和k1是相等的。但是连续两次流动性操作之间是可以存在多次资产（代币）交易的。由于资产交易手续费的存在，虽然是恒定乘积算法，但是这个乘积值K实质上是在慢慢变大的，于是这两个K之间就会有差额了。
    */
    // 计算并发送手续费给feeTo地址
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        // feeTo的地址
        address feeTo = ICherryFactory(factory).feeTo();
        // feeTo地址不能是0地址
        feeOn = feeTo != address(0);

        // 使用一个局部变量记录过去某时刻的恒定乘积中的k的值。
        // 使用局部变量可以减少gas
        uint _kLast = kLast;
        // 如果feeOn是开的
        if (feeOn) {
            // 如果旧的k值不为0
            if (_kLast != 0) {
                // rootK = _reserve0 * _reserve1开根，后面用k2表示
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                // rootKLast = 旧的k值开根，后面用k1表示
                uint rootKLast = Math.sqrt(_kLast);
                // 如果 k2 > k1
                if (rootK > rootKLast) {
                    // 分子 = 总供应量 * （k2 - k1）
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
					
                    // 分母 = k2 * 5 + k1
					/*
					5是这么来的(1/delta -1)
					其中delta=分配给团队的/总的手续费，uniswap分配给团队的是0.05%，总的是0.30
					所以0.05/0.30=1/6
					1/(1/6)-1=5
					你是0.1/0.3=1/3
					(1/(1/3)-1)=2
					*/
					
                    uint denominator = rootK.mul(5).add(rootKLast);
                    // 流动性 = 分子 / 分母
                    // Sm = (根号k2 - 根号k1)*S1 / 5 * 根号k2 + 根号k1
                    uint liquidity = numerator / denominator;
                    // 如果流动性大于0，就将流动性分配给feeTo地址
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;

        }
    }

    // 增发流动性代币给流动性提供者
    function mint(address to) external lock returns (uint liquidity) {

        // 获取当前交易对的储备量
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        // 合约里token0的余额
        uint balance0 = IERC20(token0).balanceOf(address(this));
        // 合约里token1的余额
        uint balance1 = IERC20(token1).balanceOf(address(this));
        // token0的余额 - 储备量0
        uint amount0 = balance0.sub(_reserve0);
        // token1的余额 - 储备量1
        uint amount1 = balance1.sub(_reserve1);

        // 如果feeOn开关时打开了的话
        bool feeOn = _mintFee(_reserve0, _reserve1);

        // 使用一个局部变量来保存已经发行流动性代币的总量。这样可以少操作状态变量，节省gas
        uint _totalSupply = totalSupply;

        // 如果是初次提供流动性
        if (_totalSupply == 0) {
            // 流动性 = amount0 * amount1 开根号 - 最小流动性
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            // 增发最小流动性到0地址
            _mint(address(0), MINIMUM_LIQUIDITY);
            // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {// 如果不是初次提供流动性的话
            // 流动性 = amount0 * 代币总量 / _reserve0 > amount1 * 代币总量 / _reserve1 : amount0 * 代币总量 / _reserve0,amount1 * 代币总量 / _reserve1
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }

        // 增发的流动性必须大于0，等于0相当于无增发
        require(liquidity > 0, 'Cherry: INSUFFICIENT_LIQUIDITY_MINTED');

        // 增发新的流动性给流动性接收者
        _mint(to, liquidity);

        // 更新当前保存的恒定乘积中两种资产的值
        _update(balance0, balance1, _reserve0, _reserve1);

        // 如果手续费打开了，更新最近一次的乘积值。该值不随平常的代币交易更新，仅用来流动性供给时计算开发团队手续费
        if (feeOn) kLast = uint(reserve0).mul(reserve1);

        // 监听增发事件
        emit Mint(msg.sender, amount0, amount1);
    }

    // 销毁
    function burn(address to) external lock returns (uint amount0, uint amount1) {

        // 获取当前交易对的储备量
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        // 使用一个局部变量来保存token0
        address _token0 = token0;
        // 使用一个局部变量来保存token1
        address _token1 = token1;

        // 合约里token0的余额
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        // 合约里token1的余额
        uint balance1 = IERC20(_token1).balanceOf(address(this));

        // 用户的流动性的余额
        uint liquidity = balanceOf[address(this)];

        // 如果feeOn开关时打开了的话
        bool feeOn = _mintFee(_reserve0, _reserve1);

        // 使用一个局部变量来保存已经发行流动性代币的总量。这样可以少操作状态变量，节省gas
        uint _totalSupply = totalSupply;

        // 用户的流动性的余额 * token0的余额 / 发行流动性代币的总量
        amount0 = liquidity.mul(balance0) / _totalSupply;
        // 用户的流动性的余额 * token1的余额 / 发行流动性代币的总量
        amount1 = liquidity.mul(balance1) / _totalSupply;

        // 确保amount0和amount1都大于0
        require(amount0 > 0 && amount1 > 0, 'Cherry: INSUFFICIENT_LIQUIDITY_BURNED');

        // 移除流动性
        _burn(address(this), liquidity);

        // 转amount0数量的_token0给to地址
        _safeTransfer(_token0, to, amount0);
        // 转amount1数量的_token1给to地址
        _safeTransfer(_token1, to, amount1);

        // 合约里token0的余额
        balance0 = IERC20(_token0).balanceOf(address(this));
        // 合约里token1的余额
        balance1 = IERC20(_token1).balanceOf(address(this));

        // 更新
        _update(balance0, balance1, _reserve0, _reserve1);

        // 如果手续费打开了，更新最近一次的乘积值。该值不随平常的代币交易更新，仅用来流动性供给时计算开发团队手续费
        if (feeOn) kLast = uint(reserve0).mul(reserve1);

        // 监听销毁事件
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // 实现两种资产之间的兑换
    // 参数为：购买的token0的数量，购买的token1的数量，接收者地址，接收后执行回调时的传递数据
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        // 校验输入参数不能为0，不作无意义的事
        require(amount0Out > 0 || amount1Out > 0, 'Cherry: INSUFFICIENT_OUTPUT_AMOUNT');

        // 获取当前交易对的储备量
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        // 校验购买的数量必须小于reverse，否则没有那么多代币卖。根据恒定乘积计算公式，等于也是不行的，那样输入就是无穷大
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'Cherry: INSUFFICIENT_LIQUIDITY');

        // 局部变量，保存当前交易对的代币余额
        uint balance0;
        // 局部变量，保存当前交易对的代币余额
        uint balance1;

        /*
            {}，它是一个特殊的语法，注释说是用来避免堆栈过深错误。
            为什么会有堆栈过深错误呢，因为以太坊虚拟机（EVM）访问堆栈时最多只能访问16个插槽，当访问的插槽数超过16个时在编译时就会产生stack too deep errors。
            这个错误产生的原因也比较复杂（比如函数内参数、返回参数及局部变量过多，或者引用过深等），和部分操作码也有一定关联。
            但是这里应该是函数内局部变量过多引起的。
        */
        {
            // token0地址
            address _token0 = token0;
            // token1地址
            address _token1 = token1;

            // 接收者的地址不能为token0地址，也不能为token1地址
            require(to != _token0 && to != _token1, 'Cherry: INVALID_TO');

            // 将amount0Out数量的token0转给to
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            // 将amount1Out数量的token1转给to
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
            //
            if (data.length > 0) ICherryCallee(to).cherryCall(msg.sender, amount0Out, amount1Out, data);

            // token0的余额
            balance0 = IERC20(_token0).balanceOf(address(this));
            // token1的余额
            balance1 = IERC20(_token1).balanceOf(address(this));
        }

        // 输入的amount0的数量
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        // 输入的amount1的数量
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;

        //  校验输入参数不能为0，不作无意义的事
        require(amount0In > 0 || amount1In > 0, 'Cherry: INSUFFICIENT_INPUT_AMOUNT');

        /*
            进行最终的恒定乘积验证，V2版本的验证公式为：(x1 - 0.003 * xin) * (y1 - 0.003 * yin) >= x0 * y0，注意这里的x1和y1不是reserve,而是balance，而x0和y0是reserve。xin和yin为注入的资产数量，因此要扣除千分之三的交易手续费。
            这个公式的意思为新的恒定乘积的积必须大于旧的值，因为此时reserve未更新，所以使用的是balance，验证完成后reserve会更新为balance。
            xin和yin中任意一个为0，就变成V1版本的验证公式了
        */
        {
            uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
            require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000 ** 2), 'Cherry: K');
        }

        // 更新恒定乘积中的资产值reserve为balance
        _update(balance0, balance1, _reserve0, _reserve1);

        // 监听Swap事件
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // 强制交易对合约中两种代币的实际余额和保存的恒定乘积中的资产数量一致（多余的发送给调用者）。
    // 注意：任何人都可以调用该函数来获取额外的资产（前提是如果存在多余的资产）。
    function skim(address to) external lock {
        address _token0 = token0;
        // gas savings
        address _token1 = token1;
        // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // 强制保存的恒定乘积的资产数量为交易对合约中两种代币的实际余额，用于处理一些特殊情况。
    // 通常情况下，交易对中代币余额和保存的恒定乘积中的资产数量是相等的。
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}

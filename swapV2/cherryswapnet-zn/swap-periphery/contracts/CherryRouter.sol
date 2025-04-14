// 上部分：https://blog.csdn.net/weixin_39430411/article/details/109152019?utm_medium=distribute.pc_relevant.none-task-blog-baidujs_title-0&spm=1001.2101.3001.4242

// 下部分：https://blog.csdn.net/weixin_39430411/article/details/109152084?utm_medium=distribute.pc_relevant.none-task-blog-2%7Edefault%7EBlogCommendFromBaidu%7Edefault-5.control&depth_1-utm_source=distribute.pc_relevant.none-task-blog-2%7Edefault%7EBlogCommendFromBaidu%7Edefault-5.control

/*
资产交易函数分类
    2.1、 TOKEN => TOKEN
    就是两种ERC20代币交易，可分为：
    指定卖出代币数量，得到另一种代币，函数为swapExactTokensForTokens。
    指定买进代币数量，卖出另一种代币，函数为swapTokensForExactTokens。

    2.2、ETH => TOKEN
    ETH兑换成ERC20代币，也分为两种：
    指定卖出ETH数量，得到另一种ERC20代币，函数为swapExactETHForTokens。
    指定买进ERC20代币数量，卖出ETH，函数为swapETHForExactTokens。

    2.3、TOKEN => ETH
    ERC20代币兑换成ETH。等等，有人会说这不是和 ETH => TOKEN 一样的么，既然能通过交易链实现 ETH => TOKEN，那么必能反向通过该交易链实现 TOKEN => ETH。
    是这样的没错，但是因为不能直接交易ETH，所以会涉及到一个ETH和WETH的相兑换（转换发生在不同方向的交易链的不同阶段），因此实现逻辑还是不同的，所以这里提供了另外两个接口。
    指定卖出ERC20代币数量，得到ETH，函数为swapExactTokensForETH。
    指定买进ETH数量，卖出另一种ERC20代币，函数为swapTokensForExactETH。

    2.4、支持FeeOnTransferTokens函数
    此外还有三个支持FeeOnTransferTokens函数。注意它们的函数名称，均表示指定卖出资产数量。
    也就是说它们只能用于交易链中指定卖出资产数量这种场景，不支持指定买进资产的场景中进行的反向交易链数值计算，因此只有3个该类函数。

    个人认为是因为此类资产在转移过程中可能会有损耗，但损耗到底多少是无法知晓的。
    因此指定买进资产数量反推卖出资产数量的话，是无法得到的。
    因为该值为计算得到的值加上损耗值。如果指定卖出资产数量的话，
    每个交易对的实际卖出资产数量和最终接收的买进资产数量均可以通过比较相应地址交易前后的资产余额来计算出，因此此种交易场景是可行的。

    因此2.1-2.3三种交易类型每种类型只有一个支持FeeOnTransferTokens函数，分别为：
    TOKEN => TOKEN 为 swapExactTokensForTokensSupportingFeeOnTransferTokens函数。
    ETH => TOKEN 为swapExactETHForTokensSupportingFeeOnTransferTokens函数。
    TOKEN => ETH 为swapExactTokensForETHSupportingFeeOnTransferTokens函数。
    综合得到Router2合约用于资产交易的对外接口共分四类9个接口。

    三、总结
    从前面的学习中可以看出，虽然资产交易对外提供了四类共9个接口，
    但来回就是对两个核心_swap函数的调用。
    其中支持使用转移的代币支付手续费的接口中，
    转移资产的实际数量不再等于根据恒定乘积计算出来的结果值，
    而需要根据相应地址的两次资产余额相减计算出来。
    交易链中如果有涉及到ETH交易的，
    需要在交易链的对应阶段（开始或者结束阶段）进行ETH/WETH的兑换。
    因为UniswapV2交易对全部为ERC20/ERC20交易对，因此交易链中间流程不可能有ETH出现。
*/

pragma solidity =0.6.6;

import './interfaces/ICherryPair.sol';
import './interfaces/ICherryFactory.sol';
import './interfaces/ICherryRouter02.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

import './libraries/CherryLibrary.sol';
import './libraries/SafeMath.sol';
import './libraries/TransferHelper.sol';

contract CherryRouter is ICherryRouter02 {

    // 引入安全数学运算库
    using SafeMath for uint;

    // 工厂合约地址
    address public immutable override factory;
    // WETH合约地址
    address public immutable override WETH;

    // 修饰符。判定当前区块（创建）时间不能超过最晚交易时间
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'CherryRouter: EXPIRED');
        _;
    }

    // 构造函数
    constructor(address _factory, address _WETH) public {
        // 工厂合约地址
        factory = _factory;
        // WETH合约地址
        WETH = _WETH;
    }

    // 接收ETH的函数receive。
    // 从Solidity 0.6.0起，没有匿名回调函数了。
    // 它拆分成两个，一个专门用于接收ETH，就是这个receive函数。
    // 另外一个在找不到匹配的函数时调用，叫fallback函数。
    // 该receive函数限定只能从WETH合约直接接收ETH，也就是在WETH提取为ETH时。
    // 注意仍然有可以有别的方式来向此合约直接发送以太币，例如设置为矿工地址等。
    receive() external payable {
        assert(msg.sender == WETH);
    }

    // 添加流动性
    function _addLiquidity(
        // tokenA的地址
        address tokenA,
        // tokenB的地址
        address tokenB,
        // 期望得到的tokenA的数量
        uint amountADesired,
        // 期望得到的tokenB的数量
        uint amountBDesired,
        // 最少能得到的tokenA的数量
        uint amountAMin,
        // 最少能得到的tokenB的数量
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {

    // 如果交易对不存在，就创建交易对
    if (ICherryFactory(factory).getPair(tokenA, tokenB) == address(0)) {
        ICherryFactory(factory).createPair(tokenA, tokenB);
    }

    // 获取tokenA和tokenB的储备量。如果是刚创建的，就都是0
    (uint reserveA, uint reserveB) = CherryLibrary.getReserves(factory, tokenA, tokenB);
        // 如果reserveA和reserveB都为0
        if (reserveA == 0 && reserveB == 0) {
            // 那么，这两个值对应相等
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else { // 否则
            // amountBOptimal = amountADesired * reserveB / reserveA
            uint amountBOptimal = CherryLibrary.quote(amountADesired, reserveA, reserveB);
                // 如果amountBOptimal <= amountBDesired
                if (amountBOptimal <= amountBDesired) {
                    // 要求amountBOptimal >= amountBMin
                    require(amountBOptimal >= amountBMin, 'CherryRouter: INSUFFICIENT_B_AMOUNT');
                    // 这两个值对应相等
                    (amountA, amountB) = (amountADesired, amountBOptimal);
                } else { // 否则
                    // amountBOptimal = amountADesired * reserveA / reserveB
                    uint amountAOptimal = CherryLibrary.quote(amountBDesired, reserveB, reserveA);
                    // 要求amountAOptimal <= amountADesired
                    assert(amountAOptimal <= amountADesired);
                    // 要求amountAOptimal >= amountAMin
                    require(amountAOptimal >= amountAMin, 'CherryRouter: INSUFFICIENT_A_AMOUNT');
                    // 这两个值对应相等
                    (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // 添加流动性
    // 函数返回值是实际注入的两种代币数量和得到的流动性代币数量
    function addLiquidity(
        // tokenA的地址
        address tokenA,
        // tokenB的地址
        address tokenB,
        // 期望得到的tokenA的数量
        uint amountADesired,
        // 期望得到的tokenB的数量
        uint amountBDesired,
        // 最少应该投入的tokenA的数量
        uint amountAMin,
        // 最少应该投入的tokenB的数量
        uint amountBMin
        // 接收流动性代币的地址
        address to,
        // 最迟交易时间
        // 这里deadline从UniswapV1就开始存在了，主要是保护用户，不让交易过了很久才执行，超过用户预期。
        uint deadline
        ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {

        // 调用_addLiquidity函数计算需要向交易对合约转移（注入）的实际代币数量
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        // 计算tokenA和tokenB的交易对的地址
        address pair = CherryLibrary.pairFor(factory, tokenA, tokenB);

        // 将实际注入的代币转移至交易对
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);

        // 调用交易对合约的mint函数来给接收者增发流动性
        liquidity = ICherryPair(pair).mint(to);
    }

    // 添加与ETH的流动性。因为交易对都是ERC20交易对，所以注入ETH会先自动转换为等额WETH，兑换比例为1:1
    function addLiquidityETH(
        // token的地址
        address token,
        // 期望得到的tokenA的数量
        uint amountTokenDesired,
        // 最少应该投入的tokenA的数量
        uint amountTokenMin,
        // 最少应该投入的ETH的数量
        uint amountETHMin,
        // 接收流动性代币的地址
        address to,
        // 最迟交易时间
        // 这里deadline从UniswapV1就开始存在了，主要是保护用户，不让交易过了很久才执行，超过用户预期。
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        // 第一行。调用_addLiquidity函数来计算优化后的注入代币值
        (amountToken, amountETH) = _addLiquidity(
        token,
        WETH,
        amountTokenDesired,
        msg.value,
        amountTokenMin,
        amountETHMin
    );
        // 获取交易对地址。注意它获取的方式仍然是计算得来
        address pair = CherryLibrary.pairFor(factory, token, WETH);
        // 将其中一种代币token转移到交易对中（转移的数量为由第一行计算得到）
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        // 将ETH兑换成WETH，它调用了WETH合约的兑换接口，这些接口在IWETH.sol中定义。兑换的数量也在第一行中计算得到。当然，如果ETH数量不够，则会重置整个交易
        IWETH(WETH).deposit{value: amountETH}();
        // 将刚刚兑换的WETH转移至交易对合约，注意它直接调用的WETH合约，因此不是授权交易，不需要授权。
        // 另外由于WETH合约开源，可以看到该合约代码中转移资产成功后会返回一个true，所以使用了assert函数进行验证
        assert(IWETH(WETH).transfer(pair, amountETH));
        // 调用交易对合约的mint方法来给接收者增发流动性
        liquidity = ICherryPair(pair).mint(to);
        // 如果调用进随本函数发送的ETH数量msg.value有多余的（大于amountETH,也就是兑换成WETH的数量），那么多余的ETH将退还给调用者
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // 移除流动性 tokenA  tokenB
    function removeLiquidity(
        // tokenA的地址
        address tokenA,
        // tokenB的地址
        address tokenB,
        // 移除的流动性数量
        uint liquidity,
        // 最少能得到的tokenA代币的数量
        uint amountAMin,
        // 最少能得到的tokenB代币的数量
        uint amountBMin,
        // 接收代币的地址
        address to,
        // 最迟交易时间
        // 这里deadline从UniswapV1就开始存在了，主要是保护用户，不让交易过了很久才执行，超过用户预期。
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        // 第一行。计算两种代币的交易对地址，注意它是计算得来，而不是从factory合约查询得来，所以就算该交易对不存在，得到的地址也不是零地址
        address pair = CherryLibrary.pairFor(factory, tokenA, tokenB);
        // 调用交易对合约的授权交易函数，将要燃烧的流动性转回交易对合约。
        // 如果该交易对不存在，则第一行代码计算出来的合约地址的代码长度就为0，调用其transferFrom函数就会报错重置整个交易，所以这里不用担心交易对不存在的情况
        ICherryPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        // 调用交易对的burn函数，移除掉刚转过去的流动性代币，提取相应的两种代币给接收者
        (uint amount0, uint amount1) = ICherryPair(pair).burn(to);
        // 将结果排下序（因为交易对返回的提取代币数量的前后顺序是按代币地址从小到大排序的），使输出参数匹配输入参数的顺序
        (address token0,) = CherryLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);

        // 确保提取的数量不能小于用户指定的下限，否则重置交易。
        // 为什么会有这个保护呢，因为提取前可以存在多个交易，使交易对的两种代币比值（价格）和数量发生改变，从而达不到用户的预期值
        require(amountA >= amountAMin, 'CherryRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'CherryRouter: INSUFFICIENT_B_AMOUNT');
    }

    // 移除对标的ETH的流动性
    // 函数名多了ETH。它代表着用户希望最后接收到ETH，也就意味着该交易对必须为一个TOKEN/WETH交易对。
    // 只有交易对中包含了WETH代币，才能提取交易对资产池中的WETH，然后再将WETH兑换成ETH给接收者
    function removeLiquidityETH(
        // 代币的地址
        address token,
        // 移除的数量
        uint liquidity,
        // 最少能得到的token的数量
        uint amountTokenMin,
        // 最少能得到的ETH的数量
        uint amountETHMin,
        // 接收代币的地址
        address to,
        // 最迟交易时间
        // 这里deadline从UniswapV1就开始存在了，主要是保护用户，不让交易过了很久才执行，超过用户预期。
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        // 直接调用上一个函数removeLiquidity来进行流动性移除操作，只不过将提取资产的接收地址改成本合约。
        // 为什么呢？因为提取的是WETH，用户希望得到ETH，所以不能直接提取给接收者，还要多一步WETH/ETH兑换操作
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        // 将燃烧流动性提取的另一种ERC20代币（非WETH）转移给接收者
        TransferHelper.safeTransfer(token, to, amountToken);
        // 将移除流动性提取的WETH换成ETH
        IWETH(WETH).withdraw(amountETH);
        // 将兑换的ETH发送给接收人。因为调用了removeLiquidity函数，同样需要用户事先进行授权
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // 移除流动性，同时提取交易对资产池中的两种ERC20代币。
    // 它和removeLiquidity函数的区别在于本函数支持使用线下签名消息来进行授权验证，从而不需要提前进行授权（这样会有一个额外交易），授权和交易均发生在同一个交易里
    /*
        和removeLiquidity函数相比，它输入参数多了bool approveMax及uint8 v, bytes32 r, bytes32 s。approveMax的含义为是否授权为uint256最大值(2 ** 256 -1)，
        如果授权为最大值，在授权交易时有特殊处理，不再每次交易减少授权额度，相当于节省gas。这个核心合约学习二中也有提及。
        v,r,s用来和重建后的签名消息一起验证签名者地址，具体见核心合约学习二中的permit函数学习
    */
    function removeLiquidityWithPermit(
        // tokenA的地址
        address tokenA,
        // tokenB的地址
        address tokenB,
        // 移除的流动性数量
        uint liquidity,
        // 最少能得到的tokenA代币的数量
        uint amountAMin,
        // 最少能得到的tokenB代币的数量
        uint amountBMin,
        // 接收代币的地址
        address to,
        // 最迟交易时间
        // 这里deadline从UniswapV1就开始存在了，主要是保护用户，不让交易过了很久才执行，超过用户预期。
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        // 计算交易对地址，注意不会为零地址
        address pair = CherryLibrary.pairFor(factory, tokenA, tokenB);
        // 根据是否为最大值设定授权额度
        uint value = approveMax ? uint(-1) : liquidity;
        // 调用交易对合约的permit函数进行授权
        ICherryPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // 调用removeLiquidity函数进行移除流动性从而提取代币的操作。因为在上一行代码里已经授权了，所以这里和前两个函数有区别，不需要用户提前进行授权了
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    // 功能同removeLiquidityWithPermit类似，只不过将最后提取的资产由TOKEN变为ETH
    function removeLiquidityETHWithPermit(
        // token的地址
        address token,
        // 移除的流动性数量
        uint liquidity,
        // 最少能得到的token代币的数量
        uint amountTokenMin,
        // 最少能得到的ETH代币的数量
        uint amountETHMin,
        // 接收代币的地址
        address to,
        // 最迟交易时间
        // 这里deadline从UniswapV1就开始存在了，主要是保护用户，不让交易过了很久才执行，超过用户预期。
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        // 计算交易对地址，注意不会为零地址
        address pair = CherryLibrary.pairFor(factory, token, WETH);
        // 根据是否为最大值设定授权额度
        uint value = approveMax ? uint(-1) : liquidity;
        // 调用交易对合约的permit函数进行授权
        ICherryPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // 调用removeLiquidity函数进行移除流动性从而提取代币的操作。因为在上一行代码里已经授权了，所以这里和前两个函数有区别，不需要用户提前进行授权了
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    /*
        名字很长，从函数名字中可以看到，它支持使用转移的代币支付手续费（支持包含此类代币交易对）。
        为什么会有使用转移的代币支付手续费这种提法呢？假定用户有某种代币，他想转给别人，但他还必须同时有ETH来支付手续费，
        也就是它需要有两种币，转的币和支付手续费的币，这就大大的提高了人们使用代币的门槛。于是有人想到，
        可不可以使用转移的代币来支付手续费呢？有人也做了一些探索，由此衍生了一种新类型的代币，ERC865代币，
        它也是ERC20代币的一个变种。ERC865代币的详细描述见ERC865: Pay transfer fees with tokens instead of ETH。
        然而本合约中的可支付转移手续费的代币却并未指明是ERC865代币，但是不管它是什么代币，
        我们可以简化为一点：此类代币在转移过程中可能发生损耗（损耗部分发送给第三方以支付整个交易的手续费），
        因此用户发送的代币数量未必就是接收者收到的代币数量。

        函数返回参数及removeLiquidity函数返回值中没有了amountToken。
        因为它的一部分可能要支付手续费，所以removeLiquidity函数的返回值不再为当前接收到的代币数量。
        不管损耗多少，它把本合约接收到的所有此类TOKEN直接发送给接收者。
        WETH不是可支付转移手续费的代币，因此它不会有损耗
    */

    // 功能和removeLiquidityETH函数相同，但是支持使用token支付费用
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        // token的地址
        address token,
        // 移除的流动性数量
        uint liquidity,
        // 最少能得到的token代币的数量
        uint amountTokenMin,
        // 最少能得到的ETH代币的数量
        uint amountETHMin,
        // 接收代币的地址
        address to,
        // 最迟交易时间
        // 这里deadline从UniswapV1就开始存在了，主要是保护用户，不让交易过了很久才执行，超过用户预期。
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // 功能同removeLiquidityETHSupportingFeeOnTransferTokens函数相同，但是支持使用链下签名消息进行授权
    function removeLiquidityETHWithPeritSupportingFeeOnTransferTokens(
        // token的地址
        address token,
        // 移除的流动性数量
        uint liquidity,
        // 最少能得到的token代币的数量
        uint amountTokenMin,
        // 最少能得到的ETH代币的数量
        uint amountETHMin,
        // 接收代币的地址
        address to,
        // 最迟交易时间
        // 这里deadline从UniswapV1就开始存在了，主要是保护用户，不让交易过了很久才执行，超过用户预期。
        uint deadline
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = CherryLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        ICherryPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

/*
    UniswapV2支持交易链模式。也就假定有A/B 和B/C 这两个交易对（但不是存在A/C交易对），
    我们可以在一个交易内先将A总换成B，然后再将B兑换成C，这样就相当于A兑换成了C。
    整个交换流程为：A => B => C ，顺序涉及的三种代币为A,B,C。

    path顾名思义就指这条路径的，它的内容是交易链中依次出现的各代币地址。
    因此，path的内容为[addressA,addressB,addressC]。

    amounts代表什么呢，它代表整个交易过程中交易链依次涉及的代币数量。在A => B => C 交易链中，amounts的内容为：[amountA,amountB,amountC]。
    因为初始资产只能卖出，所以amounts[0]代表卖出的初始资产数量，在本例中为amountA。
    而最终得到的资产只能买进，所以amounts数组的最后一个元素代表买进的最终资产数量，例如amountC。
    数组中间的元素代表涉及到的中间代币的数量，例如amountB，它们是前一个交易对（A/B交易对）的买进值，同时也是下一个交易对（B/C交易对）的卖出值。
*/
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        // 函数体是一个for循环，虽然我们的path长度为3，但是交易对数量只有2个，
        // 为什么呢。其实很简单，大家想一想五线谱中的间与线的数量关系是什么？
        // 是五线四间，而这里是三个地址两个交易对。这里面的关系图是不是一样的? 😉😉😉😊😊😊。
        // 所以循环的判定条件不是通常的i < path.length，而要少一次，为i < path.length - 1
        for (uint i; i < path.length - 1; i++) {
            // 用来获取当前交易对中的两种代币地址。input就是A，output就是B
            (address input, address output) = (path[i], path[i + 1]);
            // 用来获取较小的代币地址，因为交易对内的代币地址及对应的代币数量是排序过的（按地址大小从小到大排列）
            (address token0,) = CherryLibrary.sortTokens(input, output);
            // 用来从amounts中获取当前交易对的买进值（同时也是下一交易对的卖出值，如果还有交易对的话）
            uint amountOut = amounts[i + 1];

            // 用来判断如果input（A）是较小值（交易对排过序后的较小地址为A），
            // 那么当前交易对买进的两种代币数量分别为（0，amountOut），也就是卖出A，
            // 得到amountOut数量的B；如果output（B）是较小值（交易对排过序后的较小地址为B），
            // 当前交易对买进的两种代币数量分别为（amountOut，0），同样也为卖出A，得到amountOut数量的B
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            // 用来计算当前交易对的接收地址
            // 因为UniswapV2是一个交易代币先行转入系统，所以下一个交易对就直接是前一个交易对的接收地址了（如果还有下一个交易对）。
            // 这里如果i循环到最后一次i == path.length - 2,那么后面没有交易对了，其接收地址为用户指定的接收者地址；如果未到最后一次（后面还有交易对），
            // 那么接收地址就是通过工具库计算的下一个交易对的地址
            address to = i < path.length - 2 ? CherryLibrary.pairFor(factory, output, path[i + 2]) : _to;
            // 计算了当前交易对的地址，然后调用了该地址交易对合约的swap接口，
            // 将指定买进的代币数量和接收地址及空负载（不执行回调）作为参数传给该函数。
            ICherryPair(CherryLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    // 指定卖出固定数量的某种资产，而买进另一种资产的数量不固定，该值由计算得来，同时支持交易对链（也就是上面讲到的 A => B => C模式)
    // 返回值amounts代表整个交易过程中交易链依次涉及的代币数量
    function swapExactTokensForTokens(
        // 卖出的初始资产数量
        uint amountIn,
        // 买进的另一种资产的最小值
        uint amountOutMin,
        // 交易对链
        address[] calldata path,
        // 接收者地址
        address to,
        // 最迟交易时间
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        // 用来计算当前该交易的amounts，注意它使用了自定义工具库的getAmountsOut函数进行链上实时计算的，
        // 所以得出的值是准确的最新值。amounts[0]就是卖出的初始资产数量，也就是amountIn
        amounts = CherryLibrary.getAmountsOut(factory, amountIn, path);
        // 用来验证最终买进的代币数量不能小于用户限定的最小值（防止价格波动较大，超出用户的预期）
        require(amounts[amounts.length - 1] >= amountOutMin, 'CherryRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将拟卖出的初始资产转移到第一个交易对中去，这正好映证了_swap函数的注释，必须先转移卖出资产到交易对
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CherryLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 调用_swap函数进行交易操作
        // 该函数将用户欲卖出的资产转移到了第一个交易对合约中，该资产是一种ERC20代币，因此必须先得到用户的授权。
        // 那么这里可不可以采用移除流动性的permit方式实行线下签名消息授权呢？
        // 答案是不能。因为采用这种方式授权时permit函数必须包含在ERC20代币的合约代码中。
        // 在UniswapV2中，交易对本身就是ERC20代币合约(本交易对流动性代币的合约)，它里面是包含了permit函数的。
        // 但是交易对里面的两种资产（ERC20代币）却是外部的ERC20代币合约，基本上没有这个permit函数
        _swap(amounts, path, to);
    }

    /*
        Uniswap交易对采用了恒定乘积算法，它的价格是个曲线，不是线性的。
        因此指定买进和指定卖出计算的方式是不一样的。
        于是这里便有了这两种接口（函数），然而它们的底层实现却是统一的逻辑（_swap函数）
    */
    // 指定交易时买进的资产ETH的数量，而卖出的资产数量则不指定，该值可以通过计算得来
    // 返回值amounts代表整个交易过程中交易链依次涉及的代币数量
    function swapTokensForExactTokens(
        // 买进的资产的数量
        uint amountOut,
        // 卖出资产的最大值
        uint amountInMax,
        // 交易对链
        address[] calldata path,
        // 接收者地址
        address to,
        // 最迟交易时间
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        // 用来计算当前该交易的amounts，注意它使用了自定义工具库的getAmountsOut函数进行链上实时计算的，
        // 所以得出的值是准确的最新值。amounts[0]就是卖出的初始资产数量，也就是amountOut
        amounts = CherryLibrary.getAmountsIn(factory, amountOut, path);
        // 用来验证最终卖出的代币数量不能小于用户限定的最小值（防止价格波动较大，超出用户的预期）
        require(amounts[0] <= amountInMax, 'CherryRouter: EXCESSIVE_INPUT_AMOUNT');
        // 将拟买进的初始资产转移到第一个交易对中去，这正好映证了_swap函数的注释，必须先转移卖出资产到交易对
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CherryLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 调用_swap函数进行交易操作。
        // 该函数也需要事先得到用户授权以转移初始卖出资产到交易对合约。
        _swap(amounts, path, to);
    }

    // 指定交易时卖出的资产ETH的数量，而买进的资产的数量不指定，该值可以通过计算得来
    // 返回值amounts代表整个交易过程中交易链依次涉及的代币数量
    function swapExactETHForTokens(
        // 买进资产的最小值
        uint amountOutMin,
        // 交易对链
        address[] calldata path,
        // 接收者地址
        address to,
        // 最迟交易时间
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint[] memory amounts){
        // 验证第一个代币地址必须为WETH地址。因为Uniswap交易对为ERC20/ERC20交易对，
        // 卖出ETH之前会自动转换成为等额WETH（一种ERC20代币）。
        // 第一个交易对实质上是WETH/ERC20交易对，需要在此卖出WETH，所以第一个地址（卖出的初始资产地址）必须为WETH
        require(path[0] == WETH, 'CherryRouter: INVALID_PATH');
        // 计算amounts
        amounts = CherryLibrary.getAmountsOut(factory, msg.value, path);
        // 验证最终买进的资产数量必须大于用户指定的值，防止价格波动太大
        require(amounts[amounts.length - 1] >= amountOutMin, 'CherryRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将ETH兑换成WETH
        IWETH(WETH).deposit{value: amounts[0]}();
        // 将WETH转移到第一个交易对合约中。
        // WETH代币合约源码已经公开了，该合约的资产转移函数transfer会返回一个bool值，
        // 所以不需要再调用自定义库中的safeTransferFrom函数，
        // 直接使用assert函数来断言该值必须为true即可
        // 本函数没有转移用户的ERC20代币，所以没有授权操作。ETH兑换后的WETH就在本合约里，是合约自己的资产，所以调用了WETH合约的transfer方法而不是transferFrom方法
        assert(IWETH(WETH).transfer(CherryLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        // 调用_swap函数进行交易操作
        _swap(amounts, path, to);
    }

    // 指定交易时买进的资产ETH的数量，而卖出的资产数量则不指定，该值可以通过计算得来
    // 返回值amounts代表整个交易过程中交易链依次涉及的代币数量
    function swapTokensForExactETH(
        // 买进的资产的数量
        uint amountOut,
        // 卖出的资产的最大值
        uint amountInMax,
        // 交易对链
        address[] calldata path,
        // 接收者地址
        address to,
        // 最迟交易时间
        uint deadline
    )external virtual override ensure(deadline) returns (uint[] memory amounts){
        // 验证path中最后一个必须是WETH地址
        require(path[path.length - 1] == WETH, 'CherryRouter: INVALID_PATH');
        // 通过库函数计算amounts
        amounts = CherryLibrary.getAmountsIn(factory, amountOut, path);
        // 验证计算得到的卖出资产数量必须小于用户限定的最大值，价格保护
        require(amounts[0] <= amountInMax, 'CherryRouter: EXCESSIVE_INPUT_AMOUNT');
        // 将欲卖出的资产转移到第一个交易对中
        // 此函数在转移卖出资产到第一个交易对时也需要事先授权
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CherryLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );

        // 调用_swap函数进行交易操作，注意接收者地址为本合约地址。因为从最后一个交易对得到的是WETH，并不是用户想要的ETH
        _swap(amounts, path, address(this));
        // 将本合约接收的WETH转成ETH
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        // 将兑换好的ETH发送给用户指定的接收者to
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // 不指定交易时买进的资产的数量ETH，指定卖出的资产的数量，该值可以通过计算得来
    function swapExactTokensForETH(
        // 买进的资产的数量
        uint amountIn,
        // 卖出的资产的最小值
        uint amountOutMin,
        // 交易对链
        address[] calldata path,
        // 接收者地址
        address to,
        // 最迟交易时间
        uint deadline
    )external virtual override ensure(deadline) returns (uint[] memory amounts){
        // 验证path中最后一个必须是WETH地址
        require(path[path.length - 1] == WETH, 'CherryRouter: INVALID_PATH');
        // 通过库函数计算amounts
        amounts = CherryLibrary.getAmountsOut(factory, amountIn, path);
        // 验证交易链最终买进的的WETH数量（会兑换成等额ETH）不能小于用户的限定值
        require(amounts[amounts.length - 1] >= amountOutMin, 'CherryRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将用户拟卖出的资产转入到第一个交易对中
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CherryLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 调用_swap进行交易操作，注意接收者地址为本合约地址。因为最后从交易对得到的是WETH，并不是用户想要的ETH
        _swap(amounts, path, address(this));
        // 将本合约接收的WETH转成ETH
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        // 将兑换好的ETH发送给用户指定的接收者to
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // 指定买进的资产的数量，不指定卖出的ETH的数量
    function swapETHForExactTokens(
        // 卖出的ETH的数量
        uint amountOut,
        // 交易对链
        address[] calldata path,
        // 接收者地址
        address to,
        // 最迟交易时间
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint[] memory amounts){
        // 验证第一个代币地址必须为WETH地址。因为Uniswap交易对为ERC20/ERC20交易对，
        // 卖出ETH之前会自动转换成为等额WETH（一种ERC20代币）。
        // 第一个交易对实质上是WETH/ERC20交易对，需要在此卖出WETH，所以第一个地址（卖出的初始资产地址）必须为WETH
        require(path[0] == WETH, 'CherryRouter: INVALID_PATH');
        // 因为是指定买进资产，所以利用工具库函数反向遍历来计算amounts
        amounts = CherryLibrary.getAmountsIn(factory, amountOut, path);
        // 少了一个验证计算得到的卖出ETH数量。虽然不验证时，如果amounts[0] > msg.value的话，在兑换WETH时会因为ETH不足而出错重置。
        // 所以这里还是需要验证amounts[0] <= msg.value
        require(amounts[0] <= msg.value, 'CherryRouter: EXCESSIVE_INPUT_AMOUNT');
        // 将ETH兑换成WETH
        IWETH(WETH).deposit{value: amounts[0]}();
        // 将WETH转移到第一个交易对合约中。
        // WETH代币合约源码已经公开了，该合约的资产转移函数transfer会返回一个bool值，
        // 所以不需要再调用自定义库中的safeTransferFrom函数，
        // 直接使用assert函数来断言该值必须为true即可
        // 本函数没有转移用户的ERC20代币，所以没有授权操作。ETH兑换后的WETH就在本合约里，是合约自己的资产，所以调用了WETH合约的transfer方法而不是transferFrom方法
        assert(IWETH(WETH).transfer(CherryLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        // 调用_swap函数进行交易操作
        _swap(amounts, path, to);
        // 万一由于某种原因导致合约本身的ETH数量不为0，那么此时就有可能通过了（相当于用合约已有的ETH帮你支付）。
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }


    /*
      该函数和本合约的_swap主要区别就是交易链交易过程中转移的资产数量不再提前使用工具库函数计算好，而是在函数内部根据实际数值计算。
      因为资产在实际转移过程可能会有部分损耗来支付交易费用，到底损耗多少是未知的，每种资产也是不一样的，所以无法提前通过统一库函数来计算得到。
      实际计算卖出资产的数量的方法为：在交易对中卖出的资产数量等于交易对合约地址的资产余额减去交易对合约资产池中相应的数值，假设该方法叫M。
      买进的资产数量由恒定乘积算法算出，然而该值未必就是下一个交易对的资产卖出数量。因为此类资产在从当前交易对转移到下一个交易对的过程中，
      可能存在损耗，所以下一个交易对的卖进资产也是通过方法M计算（在for的下一个循环里）。

      简单点说：
      在不支持代币支付交易手续费的交易中，前一个交易对的买进资产数量就是后一个交易对的卖出资产数量（或者接收数量）；第一个交易对的卖出资产数量就是用户直接转移的资产数量.
      在支持代币支付交易手续费的交易中，因为资产转移过程中可能有损耗，所以每一个交易对的卖出资产数量必须由方法M计算得到，包含第一个交易对的卖出资产数量。
    */

    // 支持使用转移的代币支付手续费
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            // 获取当前交易对的两种代币地址
            (address input, address output) = (path[i], path[i + 1]);
            // 将这两种代币地址进行排序
            (address token0,) = CherryLibrary.sortTokens(input, output);
            // 用来得到当前交易对合约的实例
            ICherryPair pair = ICherryPair(CherryLibrary.pairFor(factory, input, output));

            // 临时变量。代表卖出资产的数量
            uint amountInput;
            // 临时变量。代表买入资产的数量
            uint amountOutput;

            {
            // 获取交易对资产池中两种资产的值（用于恒定乘积计算的），注意这两个值是按代币地址（不是按代币数量）从小到大排过序的
            (uint reserve0, uint reserve1,) = pair.getReserves();
            // 将交易对资产池中两种资产的值和第一行中获取的两个代币地址对应起来，并保存在两个带有input和output的临时reserve变量中
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            // 计算当前交易对卖出资产的数量（交易对地址的代币余额减去交易对资产池中的值）
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            // 根据恒定乘积算法来计算当前交易对买进的资产值 。
            // 为什么要计算得买进的资产值呢？
            // 因为交易对合约的swap函数的输入参数为买进的两种代币资产值而不是卖出的两种代币资产值。
            // （这么做个人认为第一方面是因为UniswapV2是先行转入卖出资产系统，
            // 卖出的数量通过比较合约地址的代币余额与合约资产池中的相应值可以得到；
            // 第二方面是交易对合约的swap函数是个先借后还系统，
            // 函数参数为买进的资产数量可以方便的先借出相应资产）
            amountOutput = CherryLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }

            // 将计算得到的买进资产值和零值按代币地址从小到大的顺序排序，这样就会和交易对中swap函数的输入参数顺序保持一致。
            // 另一个为什么是零值呢？很显然，在交易链模式中，每个交易对只会卖出其中一种资产来买进另一种资产，而不会两种资产全买进
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));

            // 计算接收地址
            address to = i < path.length - 2 ? CherryLibrary.pairFor(factory, output, path[i + 2]) : _to;
            // 调用交易对合约的swap函数进行实际交易
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    // 指定卖出的资产的数量，不指定支持使用转移的代币支付手续费的资产的数量
    // 由于此类代币在转移过程中可能有损耗，所以最终接收者买进的资产数量不再等于恒定乘积公式计算出来的值，必须使用当前余额减去交易前余额来得到实际接收值。
    // 转移卖出资产时需要提前授权
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        // 买进资产的数量
        uint amountIn,
        // 卖出的资产的最小值
        uint amountOutMin,
        // 交易对链
        address[] calldata path,
        // 接收者地址
        address to,
        // 最迟交易时间
        uint deadline
    ) external virtual override ensure(deadline) {
        // 将用户拟卖出的资产转入到第一个交易对中
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CherryLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        // 记录接收者地址在交易链最后一个代币合约中的余额。假定 A => B => C，就是C代币的余额
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        // 调用可复用的内部函数进行实际交易
        _swapSupportingFeeOnTransferTokens(path, to);
        // 验证接收者买进的资产数量不能小于指定的最小值
        require(IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin, 'CherryRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    }

    // 指定卖出的资产ETH的数量，不指定支持使用转移的代币支付手续费的资产的数量
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        // 卖出的资产的最小值
        uint amountOutMin,
        // 交易对链
        address[] calldata path,
        // 接收者地址
        address to,
        // 最迟交易时间
        uint deadline
    ) external virtual override payable ensure(deadline){
        // 验证第一个代币地址必须为WETH地址。因为Uniswap交易对为ERC20/ERC20交易对，
        // 卖出ETH之前会自动转换成为等额WETH（一种ERC20代币）。
        // 第一个交易对实质上是WETH/ERC20交易对，需要在此卖出WETH，所以第一个地址（卖出的初始资产地址）必须为WETH
        require(path[0] == WETH, 'CherryRouter: INVALID_PATH');
        // 随函数发送的ETH就是欲卖出的资产，ETH需要兑换成WETH
        uint amountIn = msg.value;
        // 将ETH兑换成WETH
        IWETH(WETH).deposit{value: amountIn}();
        // 将WETH发送到第一个交易对，因为这里是发送本合约的WETH，所以无需授权交易
        assert(IWETH(WETH).transfer(CherryLibrary.pairFor(factory, path[0], path[1]), amountIn));
        // 记录接收者地址在交易链最后一个代币合约中的余额。假定 A => B => C，就是C代币的余额
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        // 调用_swapSupportingFeeOnTransferTokens
        _swapSupportingFeeOnTransferTokens(path, to);
        // 验证接收者买进的资产数量不能小于指定的最小值
        require(IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin, 'CherryRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    }

    // 指定卖出的资产的数量，不指定支持使用转移的代币ETH支付手续费的资产的数量
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        // 买进的资产的数量
        uint amountIn,
        // 卖出的资产的最小值
        uint amountOutMin,
        // 交易对链
        address[] calldata path,
        // 接收者地址
        address to,
        // 最迟交易时间
        uint deadline
    ) external virtual override ensure(deadline){

        // 验证path中最后一个必须是WETH地址
        require(path[path.length - 1] == WETH, 'CherryRouter: INVALID_PATH');

        // 将用户拟卖出的资产转入到第一个交易对中，这里需要提前授权
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CherryLibrary.pairFor(factory, path[0], path[1]), amountIn
        );

        //调用内部函数进行交易操作。注意，此时的接收地址为本合约地址，因为用户买进的的是ETH，而这里得到的是WETH，不能直接让用户接收，需要转换成ETH
        _swapSupportingFeeOnTransferTokens(path, address(this));

        // 获取交易链中买进的资产（WETH）数量。因为周边合约本身不存有任何资产（交易前WETH余额为0），所以本合约地址当前WETH余额就是买进的WETH数量
        uint amountOut = IERC20(WETH).balanceOf(address(this));

        // 验证买进的WETH数量要大于用户指定的最小值
        require(amountOut >= amountOutMin, 'CherryRouter: INSUFFICIENT_OUTPUT_AMOUNT');

        // 最后两行，将WETH兑换成等额ETH并发送给接收者
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // 如果amountA > 0;而且reserveA > reserveB;那么，amountB = amountA * reserveB / reserveA
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return CherryLibrary.quote(amountA, reserveA, reserveB);
    }

    // 根据恒定乘积算法，指定卖出资产的数量，计算买进资产的数量。计算时考虑了手续费，仅适用于单个交易对
    // A/B交易对中卖出A资产，计算买进的B资产的数量。注意，卖出的资产扣除了千之分三的交易手续费。其计算公式为：
    //初始条件 A * B = K
    //交易后条件 ( A + A0 ) * ( B - B0 ) = k
    //计算得到 B0 = A0 * B / ( A + A0)
    //考虑千分之三的手续费，将上式中的两个A0使用997 * A0 /1000代替，最后得到结果为 B0 = 997 * A0 * B / (1000 * A + 997 * A0 )
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)public pure virtual override returns (uint amountOut){
        return CherryLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    // 根据恒定乘积算法，指定买进资产的数量，计算卖出资产的数量。计算时考虑了手续费，仅适用于单个交易对
    // A/B交易对中买进B资产，计算卖出的A资产的数量。注意，它也考虑了手续费。它和getAmountOut函数的区别是一个指定卖出的数量，一个是指定买进的数量。因为是恒定乘积算法，价格是非线性的，所以会有两种计算方式。其计算公式为：
    //初始条件 A * B = K
    //交易后条件 ( A + A0 ) * ( B - B0 ) = k
    //计算得到 A0 = A * B0 / ( B - B0)
    //考虑千分之三的手续费，A0 = A0 * 1000 / 997，所以计算结果为 A0 = A * B0 * 1000 / (( B - B0 ) * 997)
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure virtual override returns (uint amountIn){
        return CherryLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    // getAmountsOut函数。多了一个s，代表多个，意味着它用于交易链的计算中，指定卖出资产数量，计算涉及到的每种资产数量并顺序保存在一个数组中
    // 计算链式交易中卖出某资产，得到的中间资产和最终资产的数量。例如 A/B => B/C 卖出A，得到BC的数量
    function getAmountsOut(uint amountIn, address[] memory path) public view virtual override returns (uint[] memory amounts){
        return CherryLibrary.getAmountsOut(factory, amountIn, path);
    }

    // getAmountsIn函数。多了一个s，代表多个，意味着它用于交易链的计算中，指定买进资产数量，反向推导计算出涉及到的每种资产数量并顺序保存在一个数组中
    // 计算链式交易中买进某资产，需要卖出的中间资产和初始资产数量。例如 A/B => B/C 买进C，得到AB的数量。
    // 因为从买进推导卖出是反向进行的，所以数据是反向遍历的
    function getAmountsIn(uint amountOut, address[] memory path) public view virtual override returns (uint[] memory amounts){
        return CherryLibrary.getAmountsIn(factory, amountOut, path);
    }
}
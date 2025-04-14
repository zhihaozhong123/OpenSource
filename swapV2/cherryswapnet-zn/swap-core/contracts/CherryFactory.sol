// https://blog.csdn.net/weixin_39430411/article/details/108842197

pragma solidity =0.5.16;

import './interfaces/ICherryFactory.sol';
import './CherryPair.sol';

// 工厂合约
contract CherryFactory is ICherryFactory {

    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(CherryPair).creationCode));

    // 接收手续费的地址；设置为0地址代表关闭
    address public feeTo;
    // 设置手续费地址的管理员
    address public feeToSetter;

    // 记录所有交易对的地址。前两个分别为交易对中两种ERC20代币合约的地址，最后一个是交易对合约本身的地址
    mapping(address => mapping(address => address)) public getPair;

    // 所有的交易对地址
    address[] public allPairs;

    // 创建交易对的事件
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    // 构造函数
    constructor(address _feeToSetter) public {
        // 设置手续费地址的管理员
        feeToSetter = _feeToSetter;
    }

    // 所有交易对的数量
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    // 创建交易对
    function createPair(address tokenA, address tokenB) external returns (address pair) {

        // 必须是两个不同的代币
        require(tokenA != tokenB, 'Cherry: IDENTICAL_ADDRESSES');

        // 对两种代币的合约地址从小到大排序，因为地址类型底层其实是uint160，所以也是有大小可以排序的
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        // 验证两个地址不能为零地址。为什么只验证了token0呢，因为token1比它大，它不为零地址，token1肯定也就不为零地址
        require(token0 != address(0), 'Cherry: ZERO_ADDRESS');

        //来验证交易对并未创建（不能重复创建相同的交易对）
        require(getPair[token0][token1] == address(0), 'Cherry: PAIR_EXISTS');

        // 获取交易对模板合约CherryPair的创建字节码creationCode。
        // 注意，它返回的结果是包含了创建字节码的字节数组，类型为bytes。
        // 类似的，还有运行时的字节码runtimeCode。
        // creationCode主要用来在内嵌汇编中自定义合约创建流程，特别是应用于create2操作码中，这里create2是相对于create操作码来讲的。
        // 注意该值无法在合约本身或者继承合约中获取，因为这样会导致自循环引用
        bytes memory bytecode = type(CherryPair).creationCode;

        // 使用了两个代币地址作为计算源，这就意味着，对于任意交易对，该salt是固定值并且可以线下计算出来
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));


        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        // 调用新创建的交易对合约的一个初始化方法，将排序后的代币地址传递过去。
        // 为什么要这样做呢，因为使用create2函数创建合约时无法提供构造器参数
        ICherryPair(pair).initialize(token0, token1);

        // 将交易对地址记录到map中去。
        // 因为：1、A/B交易对同时也是B/A交易对；2、但在查询交易对时，用户提供的两个代币地址并没有排序，所以需要记录两次
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;

        // 将交易对地址记录到数组中去，便于合约外部索引和遍历
        allPairs.push(pair);

        // 监听创建交易对的事件
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    // 设置feeTo的地址
    function setFeeTo(address _feeTo) external {
        // 必须是管理员才能设置
        require(msg.sender == feeToSetter, 'Cherry: FORBIDDEN');
        feeTo = _feeTo;
    }

    // 设置手续费地址的管理员
    function setFeeToSetter(address _feeToSetter) external {
        // 必须是管理员才能设置
        require(msg.sender == feeToSetter, 'Cherry: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
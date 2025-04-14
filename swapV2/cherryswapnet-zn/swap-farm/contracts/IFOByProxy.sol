pragma solidity 0.6.12;

import './libraries/cherry-swap-lib/contracts/math/SafeMath.sol';
import './libraries/cherry-swap-lib/contracts/token/BEP20/IBEP20.sol';
import './libraries/cherry-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import './libraries/cherry-swap-lib/contracts/utils/ReentrancyGuard.sol';
import "./libraries/cherry-swap-lib/contracts/proxy/Initializable.sol";

contract IFOByProxy is ReentrancyGuard, Initializable {
    // 引入安全数学运算库
    using SafeMath for uint256;
    // 引入安全erc20方法库
    using SafeBEP20 for IBEP20;

    // 代表用户的结构体
    struct UserInfo {
        uint256 amount; // 代表用户质押了多少质量的token
        bool claimed;  // 代表用户是否领取了token
    }

    // 管理员账户
    address public adminAddress;
    // 募集的token的地址
    IBEP20 public lpToken;
    // 售出的代币的地址
    IBEP20 public offeringToken;
    // IFO开始时的区块高度
    uint256 public startBlock;
    // IFO结束时的区块高度
    uint256 public endBlock;
    // 总共需要募集的token的目标数量
    uint256 public raisingAmount;
    // 总共需要售出的token的数量
    uint256 public offeringAmount;
    // 募集到的token的总量
    uint256 public totalAmount;
    // 每个用户地址映射的用户的具体信息
    mapping(address => UserInfo) public userInfo;
    // 参加IFO的所有账户地址
    address[] public addressList;

    uint256 public totalLpAmount = 0;

    // 质押事件
    event Deposit(address indexed user, uint256 amount);
    // 领取事件
    event Harvest(address indexed user, uint256 offeringAmount, uint256 excessAmount);

    // 构造函数
    constructor() public {
    }

    // 初始化IFO的信息
    function initialize(
        IBEP20 _lpToken,
        IBEP20 _offeringToken,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _offeringAmount,
        uint256 _raisingAmount,
        address _adminAddress
    ) public initializer {
        // 募集的token
        lpToken = _lpToken;
        // 售出的token
        offeringToken = _offeringToken;
        // 开始区块高度
        startBlock = _startBlock;
        // 结束区块高度
        endBlock = _endBlock;
        // 售出的token的数量，精度为1e18
        offeringAmount = _offeringAmount;
        // 募集的token的目标数量，精度为1e18
        raisingAmount = _raisingAmount;
        // 总共募集的token的数量
        totalAmount = 0;
        // 设置管理员的地址
        adminAddress = _adminAddress;
    }

    // 修饰符
    modifier onlyAdmin() {
        // 只有管理员才能操作
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    // 设置售出的token的数量，只有管理员能操作
    function setOfferingAmount(uint256 _offerAmount) public onlyAdmin {
        // 要求当前的区块高度必须小于开始的区块高度
        require(block.number < startBlock, 'no');
        offeringAmount = _offerAmount;
    }
    // 设置募集的token的数量，只有管理员能操作
    function setRaisingAmount(uint256 _raisingAmount) public onlyAdmin {
        // 要求当前的区块高度必须小于开始的区块高度
        require(block.number < startBlock, 'no');
        raisingAmount = _raisingAmount;
    }

    // 用户质押募集的token
    function deposit(uint256 _amount) public {
        // 必须要求当前的区块已经过了开始区块高度并且在结束区块高度之前，否则IFO还没开始就不能质押
        require(block.number > startBlock && block.number < endBlock, 'not ifo time');
        // 必须要求用户质押募集的token的数量要大于0
        require(_amount > 0, 'need _amount > 0');
        // 募集的token会转到合约内
        lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        // 将用户存到用户地址列表里面
        if (userInfo[msg.sender].amount == 0) {
            addressList.push(address(msg.sender));
        }
        // 同一个用户质押的token的数量累加，说明一个用户可以质押多次
        userInfo[msg.sender].amount = userInfo[msg.sender].amount.add(_amount);
        // 募集的token的总量累加
        totalAmount = totalAmount.add(_amount);
        // 监听质押的事件
        emit Deposit(msg.sender, _amount);
    }

    // 领取
    function harvest() public nonReentrant {
        // 要求当前的区块高度必须已经过了IFO的结束区块的高度
        require(block.number > endBlock, 'not harvest time');
        // 要求用户有参与过IFO质押
        require(userInfo[msg.sender].amount > 0, 'have you participated?');
        // 要求用户没有领取过
        require(!userInfo[msg.sender].claimed, 'nothing to harvest');
        // 用户应该得到的售出token的数量
        uint256 offeringTokenAmount = getOfferingAmount(msg.sender);
        // 用户应该得到的退回的质押代币的数量
        uint256 refundingTokenAmount = getRefundingAmount(msg.sender);
        // 用户领取售出的代币
        if (offeringTokenAmount > 0) {
            offeringToken.safeTransfer(address(msg.sender), offeringTokenAmount);
        }
        // 用户领取退回的质押代币
        if (refundingTokenAmount > 0) {
            lpToken.safeTransfer(address(msg.sender), refundingTokenAmount);
        }

        // 将用户领取的状态标记为true，代表已经领过了
        userInfo[msg.sender].claimed = true;

        // 监听用户领取的事件
        emit Harvest(msg.sender, offeringTokenAmount, refundingTokenAmount);
    }
    // 检查用户地址是否已经领取过了
    function hasHarvest(address _user) external view returns (bool) {
        return userInfo[_user].claimed;
    }

    // allocation 100000 means 0.1(10%), 1 meanss 0.000001(0.0001%), 1000000 means 1(100%)
    // 获取用户的分配：用户的数量 * 1e12 / 用户总的质押数量 / 1e6
    function getUserAllocation(address _user) public view returns (uint256) {
        return userInfo[_user].amount.mul(1e12).div(totalAmount).div(1e6);
    }

    // 用户可以获取到的售出代币的数量。结论是：不管募集的数量目标有没有实现，用户都可以领取到售出的代币
    function getOfferingAmount(address _user) public view returns (uint256) {
        // 如果募集的总量已经大于募集的数量，也就是私募已经达到目标，用户可以获得的售出代币的数量
        if (totalAmount > raisingAmount) {
            uint256 allocation = getUserAllocation(_user);
            return offeringAmount.mul(allocation).div(1e6);
        }
        else {
            // userInfo[_user] / (raisingAmount / offeringAmount)
            // 如果募集的总量小于募集的数量，也就是募集没有达到目标，用户可以获得的售出代币的数量
            return userInfo[_user].amount.mul(offeringAmount).div(raisingAmount);
        }
    }

    // 用户可以获取到的退回去的剩余的属于自己的募集的token的数量。结论是：私募失败，用户只是领取到售出的代币的数量
    // 而不需要退回给用户募集的token的数量
    function getRefundingAmount(address _user) public view returns (uint256) {
        // 如果募集的总量小于等于募集的数量，也就是说私募失败，那么不需要退回给用户lptoken
        if (totalAmount <= raisingAmount) {
            return 0;
        }
        uint256 allocation = getUserAllocation(_user);
        uint256 payAmount = raisingAmount.mul(allocation).div(1e6);
        return userInfo[_user].amount.sub(payAmount);
    }

    // 查询质押的所有的用户地址数量
    function getAddressListLength() external view returns (uint256) {
        return addressList.length;
    }

    // 管理员IFO结束后可提取的募集的token，可以多次提取
    function finalWithdrawLpToken(uint256 _lpAmount) public onlyAdmin {
        // 要求当前的区块高度必须已经过了IFO的结束区块高度，否则不能提取
        require(block.number > endBlock, "It's not time to withdraw");
        // 要求提取的募集的token必须是合约内的数量，太大就显示余额不足
        require(_lpAmount <= lpToken.balanceOf(address(this)), 'not enough token 0');
        // 要求提取的募集的token的总量必须是募集的token的目标总量，否则就显示可提取的数量超过了募集的目标数量
        require(totalLpAmount.add(_lpAmount) <= raisingAmount, 'over the raisingAmount');
        // 当输入提取的金额大于0时
        if (_lpAmount > 0) {
            // 将合约内的募集的token转到管理员的账户上
            lpToken.safeTransfer(address(msg.sender), _lpAmount);
        }
        // 计算总的提取的募集的代币的数量
        totalLpAmount += _lpAmount;
    }

    // 管理员IFO结束后可提取的售出的token
    function finalWithdrawOfferingToken(uint256 _offerAmount) public onlyAdmin {
        // 要求提取的售出的token必须是合约内的数量，太大就显示余额不足
        require(_offerAmount <= offeringToken.balanceOf(address(this)), 'not enough token 1');
        // 当输入的金额大于0时
        if (_offerAmount > 0) {
            // 将合约内的售出的token转到管理员的账户上
            offeringToken.safeTransfer(address(msg.sender), _offerAmount);
        }
    }

}

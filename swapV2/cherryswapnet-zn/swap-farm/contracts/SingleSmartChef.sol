pragma solidity 0.6.12;

import './libraries/cherry-swap-lib/contracts/math/SafeMath.sol';
import './libraries/cherry-swap-lib/contracts/token/BEP20/IBEP20.sol';
import './libraries/cherry-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import './libraries/cherry-swap-lib/contracts/access/Ownable.sol';

// 单币质押，这份合约只适用于质押的代币和产出的代币是相同的
contract SingleSmartChef is Ownable {

    // 引入安全数学运算库
    using SafeMath for uint256;
    // 引入安全erc20方法库
    using SafeBEP20 for IBEP20;

    // 代表用户的结构体
    struct UserInfo {
        // 代表用户质押的lptoken的数量
        uint256 amount;
        // 奖励标记
        uint256 rewardDebt;
    }

    // 代表每个池子的结构体
    struct PoolInfo {
        IBEP20 lpToken;           // lpToken合约地址
        uint256 allocPoint;       // 池子的比重
        uint256 lastRewardBlock;  // 上一个区块奖励
        uint256 accCherryPerShare; // 每个cherry的占比
    }

    // 代表质押什么代币
    IBEP20 public syrup;
    // 代表奖励什么代币
    IBEP20 public rewardToken;

    // uint256 public maxStaking;

    // 每个区块产出多少奖励代币
    uint256 public rewardPerBlock;

    // 乘积
    uint256 public BONUS_MULTIPLIER = 1;

    // 池子数组
    PoolInfo[] public poolInfo;

    // 用户地址映射到每个用户的具体信息
    mapping(address => UserInfo) public userInfo;

    // 总的质押量
    uint256 public totalDeposit;
    // 总的比重
    uint256 private totalAllocPoint = 0;
    // 开始区块
    uint256 public startBlock;
    // 结束区块
    uint256 public bonusEndBlock;

    // 质押事件
    event Deposit(address indexed user, uint256 amount);
    // 提取事件
    event Withdraw(address indexed user, uint256 amount);
    // 紧急提取事件
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        IBEP20 _syrup,
        IBEP20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        // 质押什么代币
        syrup = _syrup;
        // 奖励什么代币
        rewardToken = _rewardToken;
        // 每个区块奖励多少代币
        rewardPerBlock = _rewardPerBlock;
        // 开始区块
        startBlock = _startBlock;
        // 结束区块
        bonusEndBlock = _bonusEndBlock;

        // 质押池
        poolInfo.push(PoolInfo({
            lpToken : _syrup,
            allocPoint : 1000,
            lastRewardBlock : startBlock,
            accChePerShare : 0
            }));

        totalAllocPoint = 1000;
        // maxStaking = 50000000000000000000;

    }

    // 设置停止奖励，只有管理员能触发
    function stopReward() public onlyOwner {
        bonusEndBlock = block.number;
    }

    // 获取乘积的值
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER);
        }
    }

    // 更新乘积的值
    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    // 在前端页面看到pending Reward的方法
    function pendingReward(address _user) external view returns (uint256) {
        // 第一个池子
        PoolInfo storage pool = poolInfo[0];
        // 用户
        UserInfo storage user = userInfo[_user];
        // 池子的份额
        uint256 accChePerShare = pool.accChePerShare;
        // 总共质押的代币
        uint256 lpSupply = totalDeposit;
        // 如果当前的区块高度 大于 上一个奖励区块的高度，并且总的质押量不为0
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            // 计算区块高度差，得出multiplier
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            // 计算得出che的奖励：multiplier * 每个区块奖励多少 * 池子的比重 / 池子总的比重
            uint256 cheReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            // 池子的份额 = 池子的份额 + 奖励的che * 1e12 / 总的质押量
            accChePerShare = accChePerShare.add(cheReward.mul(1e12).div(lpSupply));
        }

        // 用户质押的数量 * 池子的份额 / 1e12 - 用户的奖励标记
        return user.amount.mul(accChePerShare).div(1e12).sub(user.rewardDebt);
    }

    // 更新池子
    function updatePool(uint256 _pid) public {
        // 哪个池子
        PoolInfo storage pool = poolInfo[_pid];
        // 如果当前的区块高度 小于或者等于 上一个奖励区块，就返回
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        // 用户总共质押了多少代币
        uint256 lpSupply = totalDeposit;
        // 如果质押的代币的总量为0
        if (lpSupply == 0) {
            // 上一次奖励区块高度就为当前的区块高度
            pool.lastRewardBlock = block.number;
            // 返回
            return;
        }

        // 计算乘积
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        // 计算che的奖励：che的奖励 = 乘积 * 每个区块产出多少个che * 池子的比重 / 池子总的比重
        uint256 cheReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        // 累计的份额  = 累计的份额 + （che奖励 * 1e12） / 这个池子的lptoken余额总量
        pool.accChePerShare = pool.accChePerShare.add(cheReward.mul(1e12).div(lpSupply));
        // 上一次池子的奖励区块高度 等于 当前的区块高度
        pool.lastRewardBlock = block.number;
    }

    // 更新所有池子奖励的变量
    function massUpdatePools() public {
        // 获取到所有的池子的数量
        uint256 length = poolInfo.length;
        // 遍历所有的池子，池子在length以内
        for (uint256 pid = 0; pid < length; ++pid) {
            // 更新pid对应的池子
            updatePool(pid);
        }
    }

    // 质押代币
    function deposit(uint256 _amount) public {
        // 第一个池子
        PoolInfo storage pool = poolInfo[0];
        // 用户
        UserInfo storage user = userInfo[msg.sender];

        // require (_amount.add(user.amount) <= maxStaking, 'exceed max stake');

        // 更新池子
        updatePool(0);
        // 如果用户已经质押过了，收割操作
        if (user.amount > 0) {
            // pending = 用户的数量 * 池子的份额 / 1e12 - 用户的奖励标记
            uint256 pending = user.amount.mul(pool.accChePerShare).div(1e12).sub(user.rewardDebt);
            // 如果pending 大于 0
            if (pending > 0) {
                // 就把pending转给用户
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }

        // 如果输入的_amount的数量 大于 0
        if (_amount > 0) {
            // 将用户质押的lptoken的数量转入合约内
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

            // 用户的数量 = 用户的数量 + 质押的数量
            user.amount = user.amount.add(_amount);

            // 用户总的质押量 = 用户总的质押量 + 用户质押的数量
            totalDeposit = totalDeposit.add(_amount);
        }

        // 用户的奖励标记 = 用户的数量 * 池子的份额 / 1e12
        user.rewardDebt = user.amount.mul(pool.accChePerShare).div(1e12);

        // 监听质押事件
        emit Deposit(msg.sender, _amount);
    }

    // 提取质押的代币
    function withdraw(uint256 _amount) public {
        // 第一个池子
        PoolInfo storage pool = poolInfo[0];
        // 用户
        UserInfo storage user = userInfo[msg.sender];
        // 必须要求用户质押的数量 大于或者等于 _amount
        require(user.amount >= _amount, "withdraw: not good");

        // 更销池子
        updatePool(0);

        // 用户质押的lptoken的数量 * 池子的份额 / 1e12 - 用户的奖励标记
        uint256 pending = user.amount.mul(pool.accChePerShare).div(1e12).sub(user.rewardDebt);
        // 如果 pending大于0
        if (pending > 0) {
            // 转给用户pending
            rewardToken.safeTransfer(address(msg.sender), pending);
        }

        // 如果提取的数量_amount大于0
        if (_amount > 0) {
            // 用户质押的amount =  用户质押的amount - 输入的_amount
            user.amount = user.amount.sub(_amount);
            // 转给用户_amount
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        // 用户的奖励标记 = 用户质押的amount * 池子的份额 / 1e12
        user.rewardDebt = user.amount.mul(pool.accChePerShare).div(1e12);

        // 监听提取的事件
        emit Withdraw(msg.sender, _amount);
    }

    // 紧急提取质押的代币
    function emergencyWithdraw() public {
        // 第一个池子
        PoolInfo storage pool = poolInfo[0];
        // 用户
        UserInfo storage user = userInfo[msg.sender];
        // 将质押的代币转给用户
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        // 用户的数量为0
        user.amount = 0;
        // 用户的奖励标记为0
        user.rewardDebt = 0;

        // 监听紧急提取质押代币的事件
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // 紧急提取奖励的代币，只有管理员能操作
    function emergencyRewardWithdraw(uint256 _amount) public onlyOwner {
        // 必须要求输入的_amount要在奖励的代币的余额范围内
        require(_amount < rewardToken.balanceOf(address(this)), 'not enough token');
        // 将奖励的代币转给用户
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

}
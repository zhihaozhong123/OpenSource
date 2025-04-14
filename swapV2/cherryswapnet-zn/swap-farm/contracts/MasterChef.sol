// SPDX-License-Identifier: WTL
pragma solidity 0.6.12;

import './libraries/cherry-swap-lib/contracts/math/SafeMath.sol';
import './libraries/cherry-swap-lib/contracts/token/BEP20/IBEP20.sol';
import './libraries/cherry-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import './libraries/cherry-swap-lib/contracts/access/Ownable.sol';

import "./CherryToken.sol";
import "./SyrupBar.sol";

interface IMigratorChef {
    function migrate(IBEP20 token) external returns (IBEP20);
}

// 用户质押lptoken的主合约
contract MasterChef is Ownable {

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

    // CherryToken的合约地址
    CherryToken public cherry;
    // SyrupBar的合约地址
    SyrupBar public syrup;
    // 开发者团队的合约地址
    address public devaddr;
    // 每个区块奖励多少个cherry
    uint256 public cherryPerBlock;
    // 乘积,1024可以减半10次。
    uint256 public BONUS_MULTIPLIER = 1024;
    // 迁移合约
    IMigratorChef public migrator;

    // 池子数组
    PoolInfo[] public poolInfo;
    // 用户详细信息
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // 总比重
    uint256 public totalAllocPoint = 0;
    // 开始区块
    uint256 public startBlock;

    // 当amount为0，就是收割；当amount大于0，就是质押
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    // 提取事件
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    // 紧急提取事件
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    // 构造函数
    constructor(
        CherryToken _cherry,
        SyrupBar _syrup,
        address _devaddr,
        uint256 _cherryPerBlock,
        uint256 _startBlock
    ) public {
        // CherryToken的合约地址
        cherry = _cherry;
        // SyrupBar的合约地址
        syrup = _syrup;
        // 开发者团队的地址
        devaddr = _devaddr;
        // 每个区块产出多少cherrytoken，精度为1e18
        cherryPerBlock = _cherryPerBlock;
        // 开始区块高度
        startBlock = _startBlock;

        // 0号矿池
        poolInfo.push(PoolInfo({
            lpToken : _cherry,
            allocPoint : 0,
            lastRewardBlock : startBlock,
            accCherryPerShare : 0
            }));
        totalAllocPoint = 0;
    }

    // 更新乘积。1024->512->256->128->64->32->16->8->4->2->1 总共可以减半10次。需要到时间后手动修改这个参数。
    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    // 池子的数量
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // 增加或者更新池子
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        // 如果设置为true就增加或者更新池子
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        // 总的权重增加
        poolInfo.push(PoolInfo({// 将池子增加到池子的数组里面
            lpToken : _lpToken,
            allocPoint : _allocPoint,
            lastRewardBlock : lastRewardBlock, // 最后奖励区块如果是当前区块高度就取当前，否则就取开始区块的时间
            accCherryPerShare : 0
            }));
    }

    // 设置更新已经添加过的池子的比重
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        // 如果设置为true就更新池子
        if (_withUpdate) {
            massUpdatePools();
        }
        // 更改某一个池子的比重
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        // 这个池子的比重为当前设置的_allocPoint
        poolInfo[_pid].allocPoint = _allocPoint;
        // 如果两个比重不一样
        if (prevAllocPoint != _allocPoint) {
            // 那么，新的总的比重 = 原先总的比重 - 之前池子的比重 + 现在池子的比重
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // 设置迁移的合约地址
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // 迁移
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IBEP20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IBEP20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    // 获取乘积结果。用 (to-from)*BONUS_MULTIPLIER
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // 前端展示给用户质押lptoken得到的che的数量
    function pendingCherry(uint256 _pid, address _user) external view returns (uint256) {
        // 池子总的比重不能为0，证明是已经添加了池子，这个池子是存在的
        require(totalAllocPoint != 0, "totalAllocPoint is zero!");
        // 指定哪个池子
        PoolInfo storage pool = poolInfo[_pid];
        // 指定哪个用户
        UserInfo storage user = userInfo[_pid][_user];
        // 这个池子的份额
        uint256 accCherryPerShare = pool.accCherryPerShare;
        // 这个池子的lptoken的余额
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        // 如果当前的区块高度大于池子上一次奖励的区块高度，并且质押的lptoken的数量不为0
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            // 那么用 （当前的区块高度 - 上一次奖励的区块高度） * BONUS_MULTIPLIER
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            // che奖励 = 乘积 * 每个区块产出多少个che * 池子的比重 / 池子总的比重
            uint256 cherryReward = multiplier.mul(cherryPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            // 累计的份额  = 累计的份额 + （che奖励 * 1e12 / 这个池子的lptoken余额）
            accCherryPerShare = accCherryPerShare.add(cherryReward.mul(1e12).div(lpSupply));
        }
        // pendingCherry = 用户质押的数量 * 累计的份额 / 1e12 - 用户的奖励标记
        return user.amount.mul(accCherryPerShare).div(1e12).sub(user.rewardDebt);
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

    // 更新pid对应的池子
    function updatePool(uint256 _pid) public {
        // 哪个池子
        PoolInfo storage pool = poolInfo[_pid];
        // 如果当前的区块高度 小于或等于 上一次奖励区块高度，就返回
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        // 这个池子的lptoken的余额总量
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        // 如果lptoken的总量为0
        if (lpSupply == 0) {
            // 上一次奖励区块高度就为当前的区块高度
            pool.lastRewardBlock = block.number;
            // 返回
            return;
        }
        // 乘积
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        // che奖励 = 乘积 * 每个区块产出多少个che * 池子的比重 / 池子总的比重
        uint256 cherryReward = multiplier.mul(cherryPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        // che奖励分发给开发者团队地址5%
        cherry.mint(devaddr, cherryReward.div(20));
        // 分发给syrup合约地址 = che奖励 - 5%给开发者团队的奖励
        cherry.mint(address(syrup), cherryReward.sub(cherryReward.div(20)));
        // 累计的份额  = 累计的份额 + （che奖励 - 5%给开发者团队的che奖励 * 1e12） / 这个池子的lptoken余额
        pool.accCherryPerShare = pool.accCherryPerShare.add(cherryReward.sub(cherryReward.div(20)).mul(1e12).div(lpSupply));
        // 上一次池子的奖励区块高度 等于 当前的区块高度
        pool.lastRewardBlock = block.number;
    }

    // 质押lptoken
    function deposit(uint256 _pid, uint256 _amount) public {
        // 要求池子一定是存在的
        require(_pid != 0, 'deposit CHERRY by staking');

        // 哪个池子
        PoolInfo storage pool = poolInfo[_pid];
        // 哪个池子的用户
        UserInfo storage user = userInfo[_pid][msg.sender];

        // 更新这个池子
        updatePool(_pid);

        // 如果用户已经质押过了，收割操作
        if (user.amount > 0) {
            // pending = 用户的数量 * 池子的份额 / 1e12 - 用户的奖励标记
            uint256 pending = user.amount.mul(pool.accCherryPerShare).div(1e12).sub(user.rewardDebt);
            // 如果pending 大于 0
            if (pending > 0) {
                // 就把pending转给用户
                safeCherryTransfer(msg.sender, pending);
            }
        }

        // 如果输入的_amount的数量 大于 0
        if (_amount > 0) {
            // 将用户质押的lptoken的数量转入合约内
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

            // 用户的数量 = 用户的数量 + 质押的数量
            user.amount = user.amount.add(_amount);
        }

        // 用户的奖励标记 = 用户的数量 * 池子的份额 / 1e12
        user.rewardDebt = user.amount.mul(pool.accCherryPerShare).div(1e12);

        // 监听质押事件
        emit Deposit(msg.sender, _pid, _amount);
    }

    // 提取lptoken
    function withdraw(uint256 _pid, uint256 _amount) public {
        // 池子必须存在
        require(_pid != 0, 'withdraw CHERRY by unstaking');
        // 哪个池子
        PoolInfo storage pool = poolInfo[_pid];
        // 哪个池子的用户
        UserInfo storage user = userInfo[_pid][msg.sender];
        // 用户质押的数量必须大于输入的_amount
        require(user.amount >= _amount, "withdraw: not good");

        // 更新池子
        updatePool(_pid);

        // 用户质押的lptoken的数量 * 池子的份额 / 1e12 - 用户的奖励标记
        uint256 pending = user.amount.mul(pool.accCherryPerShare).div(1e12).sub(user.rewardDebt);
        // 如果 pending大于0
        if (pending > 0) {
            // 转给用户pending
            safeCherryTransfer(msg.sender, pending);
        }
        // 如果提取的数量_amount大于0
        if (_amount > 0) {
            // 用户质押的amount =  用户质押的amount - 输入的_amount
            user.amount = user.amount.sub(_amount);
            // 转给用户_amount
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        // 用户的奖励标记 = 用户质押的amount * 池子的份额 / 1e12
        user.rewardDebt = user.amount.mul(pool.accCherryPerShare).div(1e12);

        // 监听提取的事件
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake CHERRY tokens to MasterChef
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accCherryPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeCherryTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCherryPerShare).div(1e12);

        syrup.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw CHERRY tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accCherryPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeCherryTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCherryPerShare).div(1e12);

        syrup.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe cherry transfer function, just in case if rounding error causes pool to not have enough CACHERRY
    function safeCherryTransfer(address _to, uint256 _amount) internal {
        syrup.safeCherryTransfer(_to, _amount);
    }

    // 更新开发者团队的地址
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

}

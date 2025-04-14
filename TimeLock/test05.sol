pragma solidity ^0.6.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/SafeERC20.sol";


contract TeamTimeLock {

    using SafeMath for uint;
    using SafeERC20 for IERC20;

    // 取收益事件
    event WithDraw(address indexed operator, address indexed to, uint amount);

    // erc20代币
    IERC20 public token;

    // 每期锁仓30天，即 2592000秒
    uint constant public PERIOD = 30 days;
    // 一共有24个周期
    uint constant public  CYCLE_TIMES = 24;
    // 固定数量
    uint public fixedQuantity;
    // 开始时间
    uint public startTime;
    // 延迟时间
    uint public delay;
    // 周期
    uint public cycle;
    // 已经收益
    uint public hasReward;
    // 受益地址
    address public beneficiary;
    // 介绍
    string public introduce;

    constructor(
        address _beneficiary,
        address _token,
        uint _fixedQuantity,
        uint _startTime,
        uint _delay,
        string memory _introduce
    ) public {
        // 收益地址和合约地址都不能为0x0地址
        require(_beneficiary != address(0) && _token != address(0), "TimeLock: zero address");
        // 固定数量必须大于0
        require(_fixedQuantity > 0, "TimeLock: fixedQuantity is zero");
        beneficiary = _beneficiary;
        token = IERC20(_token);
        fixedQuantity = _fixedQuantity;
        delay = _delay;
        // 开始的时间加上延迟时间
        startTime = _startTime.add(_delay);
        introduce = _introduce;
    }

    function getBalance() public view returns (uint) {
        return token.balanceOf(address(this));
    }

    function currentTime() public view returns (uint) {
        return block.timestamp;
    }

    function getReward() public view returns (uint) {
        // 如果 cycle 已经大于 CYCLE_TIMES ，或者当下时间还没到游戏开始时间，返回0
        if (cycle >= CYCLE_TIMES || block.timestamp <= startTime) {
            return 0;
        }

        // pCycle =（当前时间 - 开始时间） / PERIOD
        uint pCycle = (block.timestamp.sub(startTime)).div(PERIOD);

        // 如果 pCycle 大于 周期时间，返回合约的余额
        if (pCycle >= CYCLE_TIMES) {
            return token.balanceOf(address(this));
        }

        // pCycle - cycle * fixedQuantity
        return pCycle.sub(cycle).mul(fixedQuantity);
    }

    function withDraw() external {
        uint reward = getReward();
        // 想要取出收益，必须要有收益
        require(reward > 0, "TimeLock: no reward");

        // pCycle =（当前时间 - 开始时间） / PERIOD
        uint pCycle = (block.timestamp.sub(startTime)).div(PERIOD);

        // 如果 pCycle >= CYCLE_TIMES ， 则 取值CYCLE_TIMES，否则取值 pCycle
        cycle = pCycle >= CYCLE_TIMES ? CYCLE_TIMES : pCycle;

        // 已经收益 = 原本已经收益 + 收益
        hasReward = hasReward.add(reward);

        // 给收益地址转账
        token.safeTransfer(beneficiary, reward);

        // 监听事件
        emit WithDraw(msg.sender, beneficiary, reward);
    }

    // 设置新的受益人地址
    function setBeneficiary(address _newBeneficiary) public {
        require(msg.sender == beneficiary, "Not beneficiary");
        beneficiary = _newBeneficiary;
    }
}

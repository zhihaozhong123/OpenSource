/**
*@copyright yangminghai  yomohoo@gmail.com
*锁仓合约大概流程
*1.发布ERC20 Token智能合约
*2.配置锁仓合约参数，发布锁仓的智能合约
*3.把要锁仓的ERC20代币转入锁仓智能合约
**
*备注：由于有些仓促，难免会存在某些设计缺陷，比如解仓条件之类，
*请谨慎引用，理解锁仓原理，并根据自己的需求重新设计
*
*/

// https://github.com/togiter/lockTokens/blob/master/contracts/Ownable.sol

pragma solidity >=0.4.26 <0.7;

contract Ownable{
    address owner;
    event OwnershipTransferred(address indexed preOwner,address indexed newOwner);
    constructor() public{
        owner = msg.sender;
    }

    modifier onlyOwner(){
        require(msg.sender == owner,"it is not owner call");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0),"not owner called");
        emit OwnershipTransferred(owner,newOwner);
        owner = newOwner;
    }
}
/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
interface ERC20Interface {
    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender)
    external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value)
    external returns (bool);

    function transferFrom(address from, address to, uint256 value)
    external returns (bool);

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

/**
 * @title SafeMath
 * @dev Unsigned math operations with safety checks that revert on error.
 */
library SafeMath {
    /**
     * @dev Multiplies two unsigned integers, reverts on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Adds two unsigned integers, reverts on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
     * reverts when dividing by zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "SafeMath: modulo by zero");
        return a % b;
    }
}

contract VestToken is Ownable{
    using SafeMath for uint256;
    //受益人结构体
    struct Beneficiary{
        address addr;  //受益人地址
        uint256 lockTokens;  //锁仓token数量
        uint256 unlockTokens; //解锁的token数量
        bool revoked;          //是否已撤销
        bool revocable;         //是否可撤销
        /**解锁条件 根据需要自己调整,常用时间作为解锁条件*/
        uint256 credits; //每次授信额度与token对应1:1
    }

    //address(this)的余额 = totalLockTokens - totalUnLockTokens;
    uint256 public totalLockTokens;    //已经锁仓的Token总量
    uint256 public totalUnlockTokens;  //已经解锁的token总量

    //锁仓人员
    mapping(address=>Beneficiary) beneficiaries;
    //token对象
    ERC20Interface token;

    //事件
    /**
    *锁仓事件
    *锁仓人，金额，是否可撤销
    */
    event EventLockTokens(address indexed addr,uint256 indexed lockTokens,bool revocable);
    /*
    *解锁token事件，受益人地址，解锁tokens
    */
    event EventUnlockTokens(address indexed addr,uint256 indexed unlockTokens);
    /*
    *撤销锁仓事件  被锁仓者
    */
    event EventRevoked(address indexed addr);


    constructor(address tokenAddr) public {
        token = ERC20Interface(tokenAddr);
        totalLockTokens = 0;
        totalUnlockTokens = 0;
    }

    // function setupTokenAddr(address addr) public onlyOwner{
    //      token = ERC20Interface(addr);
    // }
    /**
    *添加锁仓受益人
    *受益人地址，锁仓金额，是否可撤销
    */
    function increaseLockTokens(address addr,uint256 lockTokens,bool revocable) public onlyOwner {
        require(addr != address(0),"锁仓地址不能为空");
        require(lockTokens > 0,"锁仓金额必须大于0");
        require(beneficiaries[addr].addr == address(0),"该地址已经有锁仓");
        uint256 totalTokens = token.balanceOf(address(this));
        require(totalTokens > totalLockTokens.add(lockTokens).sub(totalUnlockTokens),"余额不足够锁仓了"); //该地址的余额要大于正在锁仓数量
        beneficiaries[addr] = Beneficiary({
            addr:addr,
            lockTokens:lockTokens,
            unlockTokens:0,
            revoked:false,
            revocable:revocable,
            credits:0
            });
        totalLockTokens = totalLockTokens.add(lockTokens);
        emit EventLockTokens(addr,lockTokens,revocable);
    }

    function balanceOf(address addr) view public returns(uint256) {
        return token.balanceOf(address(addr));
    }

    /**
    *触发锁仓条件进行解仓
    *addr 锁仓人信息
    *_credits 授信积分 在此为1:1兑换代币
    */
    function unlockTokensByCredits(address addr,uint _credits) public onlyOwner {
        require(addr != address(0),"锁仓人地址不能为空");
        Beneficiary storage beneficiary = beneficiaries[addr];
        require(beneficiary.revoked==false,"该地址已被撤销锁仓");
        require(beneficiary.unlockTokens.add(_credits) <= beneficiary.lockTokens,"剩余锁仓额度不足!");
        beneficiary.unlockTokens = beneficiary.unlockTokens.add(_credits); //受益人已解仓数量
        require(token.transfer(addr,_credits),"解仓转账返回失败 ");
        totalUnlockTokens = totalUnlockTokens.add(_credits); //已解仓总数
        emit EventUnlockTokens(addr,_credits);
    }

    /**
    *返回锁仓人(受益人)的信息
    *
    *_addr 锁仓人地址
    */
    function beneficiaryInfo(address _addr) view public returns(address addr,uint256 lockTokens,uint256 unLockTokens,bool revoked, bool revocable) {
        Beneficiary storage beneficiary = beneficiaries[_addr];
        addr = beneficiary.addr;
        lockTokens = beneficiary.lockTokens;
        unLockTokens = beneficiary.unlockTokens;
        revocable = beneficiary.revocable;
        revoked = beneficiary.revoked;
    }

    /*
    *撤销锁仓,前提是可以撤销
    */
    function revokedLockTokens(address _addr) public onlyOwner {
        Beneficiary storage beneficiary = beneficiaries[_addr];
        require(beneficiary.revocable==true,"该仓不可撤销");
        require(beneficiary.revoked==false,"该仓已经撤销过了");
        //解锁
        unlockTokensByCredits(_addr,beneficiary.lockTokens.sub(beneficiary.unlockTokens));
        beneficiary.revoked = true;
        emit EventRevoked(_addr);
    }

}
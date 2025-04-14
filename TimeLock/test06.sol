// https://blog.csdn.net/HiBlock/article/details/81712362
// https://www.jianshu.com/p/db7cb9431ecc
pragma solidity ^0.6.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";

contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() public {
        owner = msg.sender;
    }


    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }


    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        // 空字符串hash值
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        //内联编译（inline assembly）语言，是用一种非常底层的方式来访问EVM
        // extcodesize获取地址关联代码长度 合约地址大于0 外部账号地址为0
        // 检索代码的大小，这需要汇编
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    // 功能主要包括判断地址类型（合约地址 or 账号地址）,
    // 限定地址调用合约功能（比如限定余额充足）等；
    function sendValue(address payable recipient, uint256 amount) internal {
        // this代表当前合约本身
        // balance方法，获取当前合约的余额
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

library SafeERC20 {

    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),"SafeERC20: approve from non-zero to non-zero allowance");
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

contract TokenVesting is Ownable {

    event Released(uint256 amount);
    event Revoked();

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public beneficiary;
    uint256 public cliff;
    uint256 public start;
    uint256 public duration;
    bool public revocable;

    mapping (address => uint256) public released;
    mapping (address => bool) public revoked;

    constructor(
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        bool _revocable
    )
     public
    {
        require(_beneficiary != address(0));
        require(_cliff <= _duration);
        beneficiary = _beneficiary;
        revocable = _revocable;
        duration = _duration; // 持续锁仓时间  20 minutes
        cliff = _start.add(_cliff);
        start = _start;
    }

    // 释放erc20合约代币
    function release(IERC20 _token) public {
        uint256 unreleased = releasableAmount(_token);
        require(unreleased > 0);
        released[address(_token)] = released[address(_token)].add(unreleased);
        _token.safeTransfer(beneficiary, unreleased);
        emit Released(unreleased);
    }

    // 剩余的erc20代币返回给owner
    function revoke(IERC20 _token) public onlyOwner {
        require(revocable);
        require(!revoked[address(_token)]);

        uint256 balance = _token.balanceOf(address(this));
        uint256 unreleased = releasableAmount(_token);
        uint256 refund = balance.sub(unreleased);

        revoked[address(_token)] = true;
        _token.safeTransfer(owner, refund);
        emit Revoked();
    }

    // 可释放的erc20代币数量
    function releasableAmount(IERC20 _token) public view returns (uint256) {
        //
        return vestedAmount(_token).sub(released[address(_token)]);
    }

    // 已经vested的erc20代币数量
    function vestedAmount(IERC20 _token) public view returns (uint256) {

        uint256 currentBalance = _token.balanceOf(address(this));
        uint256 totalBalance = currentBalance.add(released[address(_token)]);

        if (block.timestamp < cliff) {
            return 0;
      } else if (block.timestamp >= start.add(duration) || revoked[address(_token)]) {
         return totalBalance;
      } else {
         return totalBalance.mul(block.timestamp.sub(start)).div(duration);
     }
    }

}


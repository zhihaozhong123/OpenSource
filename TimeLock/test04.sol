// https://www.dazhuanlan.com/2019/12/04/5de7bebb391d5/?__cf_chl_jschl_tk__=8e6104b5a1ee45d9fb2fc779d8ee224199727bfe-1611540615-0-AQpMK1EMpQ_F40seUQ7ACxbAVgXzy_5rDHsNBWXkpIHHdYtHDqD7J5JXB0RRmey5pkFdOG7O9cgNn8arlDhw4ho-QzehRq7rHAqKTv27av_v-4eQfkaQqo3Vo8FiDXziBCWwg06MBboS4kqSvldZshfKihU8pQ5kFmdzvlfneym-mzgwsWr-WVVe1B7zLobQb8FJ3hRxEAqdekDeSPfevgMx954rJEfc_67jpobmOPT3DyQJMGfN17s9gpruNHj8tEnIvH7hOLYt8iEihqJ2SC_yX1Vyw28YMpIeee45yjCEDIvjJ8lbqHlrOCcfOtBAFSPaxDaN9rWy1vTixMNaL3c
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/TimelockController.sol

// https://zhuanlan.zhihu.com/p/36439229


pragma solidity ^0.5.17;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        // 空字符串hash值
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        //内联编译（inline assembly）语言，是用一种非常底层的方式来访问EVM
        // extcodesize获取地址关联代码长度 合约地址大于0 外部账号地址为0
        // 检索代码的大小，这需要汇编
        assembly {codehash := extcodehash(account)}
        return (codehash != accountHash && codehash != 0x0);
    }

    // 功能主要包括判断地址类型（合约地址 or 账号地址）,
    // 限定地址调用合约功能（比如限定余额充足）等；
    function sendValue(address payable recipient, uint256 amount) internal {
        // this代表当前合约本身
        // balance方法，获取当前合约的余额
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success,) = recipient.call.value(amount)("");
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
        require((value == 0) || (token.allowance(address(this), spender) == 0), "SafeERC20: approve from non-zero to non-zero allowance");
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


/**
 * @title TokenTimelock
 * @dev TokenTimelock is a token holder contract that will allow a
 * beneficiary to extract the tokens after a given release time
 */
contract TokenTimelock {

    using SafeERC20 for IERC20;

    // ERC20 basic token contract being held
    IERC20 public token;

    // beneficiary of tokens after they are released
    address public beneficiary;

    // timestamp when token release is enabled
    uint256 public releaseTime;

    // 构造函数，在合约创建时运行
    // _token 是指代币的地址，代表代币的种类
    // _beneficiary 是收款的账号地址
    // _releaseTime 是一个Unix时间戳（秒），表示过了这个时间就可以释放代币
    constructor(
        IERC20 _token,
        address _beneficiary,
        uint256 _releaseTime
    )
    public
    {
        // solium-disable-next-line security/no-block-members
        require(_releaseTime > block.timestamp);
        token = _token;
        beneficiary = _beneficiary;
        releaseTime = _releaseTime;
    }

    /**
     * 这个是释放代币的函数，需要人为调用，如果调用成功，代币将转到beneficiary
     * @notice Transfers tokens held by timelock to beneficiary.
     */
    function release() public {
        // solium-disable-next-line security/no-block-members
        require(block.timestamp >= releaseTime);

        uint256 amount = token.balanceOf(address(this));
        require(amount > 0);

        token.safeTransfer(beneficiary, amount);
    }

    function currentTime() public view returns (uint) {
        return block.timestamp;
    }

    function getBalance(address _addr) view public returns (uint256){
        return balanceOf[_addr];
    }
}
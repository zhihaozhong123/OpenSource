// https://blog.csdn.net/weixin_39430411/article/details/108965441?spm=1001.2014.3001.5502

pragma solidity =0.5.16;

import './interfaces/ICherryERC20.sol';
import './libraries/SafeMath.sol';

// LP Token合约
contract CherryERC20 is ICherryERC20 {

    // 引入安全数学运算库
    using SafeMath for uint;

    // LP Token的名称
    string public constant name = 'Cherry LPs';
    // LP Token的标志
    string public constant symbol = 'Che-LP';
    // LP Token的精度
    uint8 public constant decimals = 18;
    // LP Token的总量
    uint  public totalSupply;

    // 映射的余额
    mapping(address => uint) public balanceOf;
    // 映射的限额
    mapping(address => mapping(address => uint)) public allowance;

    // 领域分离器
    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    // 钱包账号地址 映射的 nonce值
    mapping(address => uint) public nonces;

    // 批准事件
    event Approval(address indexed owner, address indexed spender, uint value);
    // 转账事件
    event Transfer(address indexed from, address indexed to, uint value);

    // 构造函数
    constructor() public {
        uint chainId;
        assembly {
            chainId := chainid
        }

        // abi.encode: 计算参数的ABI编码
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    // 增发
    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    // 销毁
    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    // 批准
    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    // 转账
    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    // 批准
    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    // 转账
    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    // 转账
    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != uint(- 1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    // 许可
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'Cherry: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'Cherry: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}

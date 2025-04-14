// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// usdt on ethereum main network: 0xdAC17F958D2ee523a2206206994597C13D831ec7
contract masterchef {

    event TransferFrom(address _from ,address _to ,uint256 _value);
    event EmergencyWithdraw(uint256 _amounts);
    // 取收益事件
    event WithDraw(address indexed operator, address indexed to, uint amount);

    IERC20 public usdt_token;
    IERC20 public erc20_token;

    IERC721 public erc721_token;

    address[] public users;
    address public owner;

    // 固定值500u
    uint256 constant public fixValue = 500 * 1e18;
    // 拥有nft的用户可以质押的数量
    uint256 public value;
    // 需要质押的usdt的总量
    uint256 constant public MAX_USDT = 200000 * 1e18;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public delayTime;

    mapping(address => bool) public isPledge;
    mapping(address => bool) public isOld;

    mapping(address => uint256) public addressBalanceInContractMap;

    mapping(address => uint256) public pledgeTimeMap;

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    constructor(IERC20 _usdtTokenAddress, IERC721 _erc721TokenAddress, uint256 _startTime, uint256 _delayTime, uint256 _endTime) {
        usdt_token = _usdtTokenAddress;
        erc721_token = _erc721TokenAddress;
        // erc20_token = _erc20TokenAddress;

        startTime = _startTime + _delayTime;
        delayTime = _delayTime;
        endTime = _endTime;

        owner = msg.sender;
    }

    // 合约内usdt的总额
    function USDTTotalInContract() public view returns(uint256) {
        return usdt_token.balanceOf(address(this));
    }

    // 普通质押功能，没有涉及到NFT
    function _pledge1(uint256 _amount) private {
        // 如果不是老用户
        if(isOld[msg.sender] == false) {
            // 必须是在质押的时间范围内
            require(block.timestamp >= startTime && block.timestamp <= endTime,"1no start yet or time over!");
            // 合约里的usdt的数量不能大于规则里的最大值20w usdt
            require(USDTTotalInContract() <= MAX_USDT,"1USDT enough!");
            // 最少质押100
            require(_amount >= 100 * 1e18,"1need 100u at lease!");
            // 输入的参数数量必须是100的整数倍
            require(_amount % (100 * 1e18) == 0,"1must 100 beishu");
            // 最大只能质押500
            require(_amount <= 500 * 1e18,"1The number of usdt pledged cannot exceed 500!");
            // 该用户质押的总量
            addressBalanceInContractMap[msg.sender] += _amount;
            // 该用户质押在这份合约内的最大量只能是500
            require(addressBalanceInContractMap[msg.sender] <= 500 * 1e18,"a maximum of 500 can be pledged!");

            // 将用户装在数组里面
            users.push(msg.sender);

            // 记录用户质押的时间
            pledgeTimeMap[msg.sender] = block.timestamp;

            // 将usdt质押到此合约内
            usdt_token.transferFrom(msg.sender,address(this),_amount);

            // 质押状态为true
            isPledge[msg.sender] = true;

            // 监听交易
            emit TransferFrom(msg.sender,address(this),_amount);

        // 如果是老用户
        }else {
            // 防止同一个用户把自己的nft转出后，变为普通用户又过来质押。只要该用户持有nft的时候进行了质押，转出后变为普通用户就无法再进行质押操作
            require(isOld[msg.sender] == false,"not the new user");
        }
    }

    // 当用户持有nft的时候
    function _pledge2 (uint256 _amount) private {
            // 必须是在质押的时间范围内
            require(block.timestamp >= startTime && block.timestamp <= endTime,"2no start yet or time over!");
            // 合约里的usdt的数量不能大于规则里的最大值20w usdt
            require(USDTTotalInContract() <= MAX_USDT,"2USDT enough!");
            // 必须保证该用户至少质押100个
            require(_amount >= 100 * 1e18,"2need 100u at lease!");
            // 输入的参数数量必须是100的整数倍
            require(_amount % (100 * 1e18) == 0,"1must 100 beishu");
            // 该用户拥有多少nft的数量
            uint256 bal = getNFTAmounts(msg.sender);
            // 用一个全局变量接收
            // balances = bal;
            // 最大可以质押的数量value
            value = fixValue + bal * 1000 * 1e18;
            // 该用户质押的总量
            addressBalanceInContractMap[msg.sender] += _amount;
            // 可以质押的最大的数量不能大于value1
            require(_amount <= value,"2 The maximum limit is exceeded!");
            // 该用户质押的总量不能大于最大可以质押的数量value1
            require(addressBalanceInContractMap[msg.sender] <= value,"22 The maximum limit is exceeded!");

            // 将用户装在数组里面
            users.push(msg.sender);

            // 记录用户质押的时间
            pledgeTimeMap[msg.sender] = block.timestamp;

            // 将usdt质押到合约内
            usdt_token.transferFrom(msg.sender,address(this),_amount);

            // 质押状态为true
            isPledge[msg.sender] = true;
            // 不是新用户
            isOld[msg.sender] = true;

            // 监听交易
            emit TransferFrom(msg.sender,address(this),_amount);
    }

    // 质押usdt
    function pledge(uint256 _amount) external returns(bool) {
        // 如果该用户没有持有nft
        if(getNFTAmounts(msg.sender)==0){
            _pledge1(_amount); 
            return true;
            // 如果该用户持有nft
        } else {
            _pledge2(_amount);
            return true;
        }
    }

    // 紧急提取合约内的usdt，只能是管理员能操作
    function emergencyWithdrawUSDTToken(uint256 _amount) public onlyOwner {
        usdt_token.transfer(owner,_amount);
    }

    // 该用户持有的nft的数量
    function getNFTAmounts(address _address) public view returns(uint256) {
        return erc721_token.balanceOf(_address);
    }

    // 获取所有的用户，同个用户也会叠加地址，不去重
    function getAllUsers() public view returns(address[] memory) {
        return users;
    }

    // 获取所有用户的数量
    function allUsersAmounts() public view returns(uint256) {
        return users.length;
    }

    // 当前时间
    function currentTime() public view returns (uint) {
        return block.timestamp;
    }

}
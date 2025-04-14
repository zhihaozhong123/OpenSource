// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// usdt on ethereum main network: 0xdAC17F958D2ee523a2206206994597C13D831ec7
contract masterchef is ReentrancyGuard {

    // 交易事件
    event safeTransferFrom(address _from ,address _to ,uint256 _value);
    // 提取事件
    event WithDraw(address indexed operator, address indexed to, uint amount);

    // 引入安全erc20方法库
    using SafeERC20 for IERC20;

    // 用户质押usdt
    IERC20 public usdt_token;
    // 用户领取erc20代币
    IERC20 public erc20_token;
    // erc721代币
    IERC721 public erc721_token;

    // 用户名单信息
    struct Whitelist {
        address wallet; // 钱包地址
        uint amount; // 数量
        uint startTiming; // 用户开始领取的时间
    }

    // 所有质押的用户数量
    address[] public users;
    // 拥有owner权限的用户
    address public owner;

    // 固定值500u
    uint256 constant public fixValue = 500 * 1e18;
    // 拥有nft的用户可以质押的数量
    uint256 public value;
    // 需要质押的usdt的总量
    uint256 constant public MAX_USDT = 200000 * 1e18;

    // 质押开始时间
    uint256 public pledgeStartTime;
    // 质押结束时间
    uint256 public pledgeEndTime;
    // 用户提取的总量
    uint public totalAmount;

    // erc20代币空投开始时间
    uint public claimStartTime;

    // 锁多久后才能领取
    uint public constant lockTime = 30 minutes;

    // 是否质押
    mapping(address => bool) public isPledge;
    // 是否是老用户
    mapping(address => bool) public isOld;

    // 用户在合约内质押的usdt的数量
    mapping(address => uint256) public addressBalanceInContractMap;

    // 用户质押usdt的次数
    mapping(address => uint256) public pledgeTimeMap;

    // 用户的具体信息
    mapping(address => Whitelist) public whitelist;

    // 领取空投代币的次数
    mapping(address => uint256) public countsMap; 

    // 修改器。权限拥有者
    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    constructor(
        address _usdtTokenAddress, 
        address _erc721TokenAddress, 
        address _erc20TokenAddress, 
        uint256 _pledgeStartTime, 
        uint256 _pledgeEndTime,
        uint256 _claimStartTime) {

        usdt_token = IERC20(_usdtTokenAddress); // 用户质押usdt
        erc721_token = IERC721(_erc721TokenAddress); // 用户拥有的nft
        erc20_token = IERC20(_erc20TokenAddress); // 用户领取的erc20代币
        
        pledgeStartTime = _pledgeStartTime; // 用户质押usdt的开始时间
        pledgeEndTime = _pledgeEndTime; // 用户质押usdt的结束时间
        claimStartTime = _claimStartTime; // 用户领取erc20代币的开始时间

        owner = msg.sender;
    }

    // 普通质押功能，没有涉及到NFT
    function _pledge1(uint256 _amount) private {
        // 如果不是老用户
        if(isOld[msg.sender] == false) {
            // 必须是在质押的时间范围内
            require(block.timestamp >= pledgeStartTime && block.timestamp <= pledgeEndTime,"1no start yet or time over!");
            // 合约里的usdt的数量不能大于规则里的最大值20w usdt
            require(USDTTotalInContract() <= MAX_USDT,"1USDT enough!");
            // 最少质押100
            require(_amount >= 100 * 1e18,"1need 100u at lease!");
            // 输入的参数数量必须是100的整数倍
            require(_amount % (100 * 1e18) == 0,"1must 100 beishu");
            // 最大只能质押500
            require(_amount <= 500 * 1e18,"1The number of usdt pledged cannot exceed 500!");
            // 该用户质押的usdt的总量
            addressBalanceInContractMap[msg.sender] += _amount;
            // 该用户质押在这份合约内的最大量只能是500
            require(addressBalanceInContractMap[msg.sender] <= 500 * 1e18,"a maximum of 500 can be pledged!");

            // 将用户装在数组里面
            users.push(msg.sender);

            // 用户账号信息绑定
            whitelist[msg.sender].wallet = msg.sender;

            // 用户usdt数量绑定
            whitelist[msg.sender].amount = addressBalanceInContractMap[msg.sender];

            // 记录用户质押的时间
            pledgeTimeMap[msg.sender] = block.timestamp;

            // 将usdt质押到此合约内
            usdt_token.safeTransferFrom(msg.sender,address(this),_amount);

            // 质押状态为true
            isPledge[msg.sender] = true;

            // 监听交易
            emit safeTransferFrom(msg.sender,address(this),_amount);

        // 如果是老用户
        }else {
            // 防止同一个用户把自己的nft转出后，变为普通用户又过来质押。只要该用户持有nft的时候进行了质押，转出后变为普通用户就无法再进行质押操作
            require(isOld[msg.sender] == false,"not the new user");
        }
    }

    // 当用户持有nft的时候
    function _pledge2 (uint256 _amount) private {
            // 必须是在质押的时间范围内
            require(block.timestamp >= pledgeStartTime && block.timestamp <= pledgeEndTime,"2no start yet or time over!");
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

            // 用户账号信息绑定
            whitelist[msg.sender].wallet = msg.sender;
            
            // 用户usdt数量绑定
            whitelist[msg.sender].amount = addressBalanceInContractMap[msg.sender];

            // 记录用户质押的时间
            pledgeTimeMap[msg.sender] = block.timestamp;

            // 将usdt质押到合约内
            usdt_token.safeTransferFrom(msg.sender,address(this),_amount);

            // 质押状态为true
            isPledge[msg.sender] = true;

            // 变成是老用户了
            isOld[msg.sender] = true;

            // 监听交易
            emit safeTransferFrom(msg.sender,address(this),_amount);
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

    function _claim() private {
        require(msg.sender == whitelist[msg.sender].wallet,"You have no qualification to claim!");
        require(erc20TokenInContract() > whitelist[msg.sender].amount,"Insufficient token balance in the contract!");
        require(block.timestamp >= claimStartTime,"Activity has not started yet!");
        require((block.timestamp >= claimStartTime + whitelist[msg.sender].startTiming),"It is not ready for claim yet!");
        require(countsMap[msg.sender] < 5, "It has been claimed in five years!");

        whitelist[msg.sender].startTiming = whitelist[msg.sender].startTiming + lockTime;

        uint qtyWidthdrawl = whitelist[msg.sender].amount;
        uint amount = qtyWidthdrawl / 5;

        totalAmount = totalAmount + amount;

        erc20_token.safeTransfer(msg.sender, amount);
        countsMap[msg.sender]++; 

        emit safeTransferFrom(address(this), msg.sender, whitelist[msg.sender].amount);        
    }

    // 领取
    function claim() external nonReentrant {
        _claim();
    }

    // 合约内usdt的总额
    function USDTTotalInContract() public view returns(uint256) {
        return usdt_token.balanceOf(address(this));
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

    // 合约内erc20代币的余额
    function erc20TokenInContract() public view returns(uint256) {
        return erc20_token.balanceOf(address(this));
    }

    // 合约内usdt代币的余额
    function USDTTokenInContract() public view returns(uint256) {
        return usdt_token.balanceOf(address(this));
    }

    // 当前时间
    function currentTime() public view returns (uint) {
        return block.timestamp;
    }

    // 用户可以领取空投的时间
    function ReleaseTime() public view returns(uint) {
        return claimStartTime + whitelist[msg.sender].startTiming;
    }

    // 获取用户已经claim了多少
    function getClaimBalance() public view returns(uint) {
        return erc20_token.balanceOf(msg.sender);
    }

    // 获取用户claim后还剩余多少可以claim
    function getBalance() public view returns(uint) {
        return (whitelist[msg.sender].amount) - getClaimBalance();
    }

    // 获取用户还能claim的次数
    function ClaimTimeBalance() public view returns(uint) {
        return 5 - countsMap[msg.sender];
    }

    // 获取用户总共能claim多少
    function canClaimAllAmounts() public view returns(uint) {
        return whitelist[msg.sender].amount;
    }

    // 转移所有权，只有owner才能执行
    function transferOwnership(address _address) public onlyOwner returns(bool) {
        // 提取的地址不能是黑洞地址
        require(_address != address(0x0),"It should be not 0x0 address!");
        owner = _address;

        return true;
    } 

    // 提取合约内的指定数量的erc20代币，只有owner才能提取
    function WithdrawERC20Token(uint256 _amounts) public onlyOwner nonReentrant returns(bool) {
        // 将一定数量的代币转让给owner
        erc20_token.safeTransfer(msg.sender,_amounts);

        emit WithDraw(address(this),msg.sender,_amounts);

        return true;
    }

    // 紧急提取合约内的所有erc20代币，只有owner才能提取
    function EmergencyWithdrawERC20Token() public onlyOwner nonReentrant returns(bool) {
        // 将合约内的代币转让给owner
        erc20_token.safeTransfer(msg.sender,erc20TokenInContract());

        emit WithDraw(address(this),msg.sender,erc20TokenInContract());

        return true;
    }

    // 提取合约内的指定数量的usdt代币，只有owner才能提取
    function WithdrawUSDTToken(uint256 _amount) public onlyOwner nonReentrant returns(bool) {
        usdt_token.safeTransfer(owner,_amount);

        emit WithDraw(address(this),msg.sender,_amount);

        return true;
    }
    
    // 紧急提取合约内的所有usdt代币，只有owner才能提取
    function EmergencyWithdrawUSDTToken() public onlyOwner nonReentrant returns(bool) {
        // 将合约内的代币转让给owner
        usdt_token.safeTransfer(msg.sender,USDTTokenInContract());

        emit WithDraw(address(this),msg.sender,USDTTokenInContract());

        return true;
    }

}
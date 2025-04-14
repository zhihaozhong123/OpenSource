// SPDX-License-Identifier: MIT
// Author: ZhiHao.Zhong
// Date: 2024-09-06
pragma solidity >0.6.0 <=0.8.24;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = _NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

contract DevotePoint is Ownable, ReentrancyGuard {
    event Gain(
        UserInfo userInfo
    );

    event Use(
        UserInfo userInfo
    );

    struct UserInfo {
        address user; // 用户
        uint256 count; // 积分数量
        uint256 currentTime; // 操作时间
        uint256 kind; // 种类
    }

    mapping(address => UserInfo) private userData;
    mapping(address => bool) private authorizedMap;

    modifier onlyAuthorized() {
        require(
            authorizedMap[msg.sender],
            "only authorized address can call."
        );
        _;
    }

    constructor() Ownable(msg.sender) {}

    function gain(address _user, uint256 _count, uint256 _kind) external onlyAuthorized nonReentrant {
        require(_count > 0,"The count can't be zero.");

        UserInfo storage userInfo = userData[_user];

        userInfo.user = _user;
        userInfo.count += _count;
        userInfo.currentTime = block.timestamp;
        userInfo.kind = _kind;

        emit Gain(userInfo);
    }

    function use(address _user, uint256 _count, uint256 _kind) external onlyAuthorized nonReentrant {
        require(_count > 0,"The count can't be zero.");

        UserInfo storage userInfo = userData[_user];
        require(_count <= userInfo.count, "The count exceed the max count.");

        userInfo.user = _user;
        userInfo.count -= _count;
        userInfo.kind = _kind;

        emit Use(userInfo);
    }

    function setAuthorizedAddress(
        address _address,
        bool _status
    ) external onlyOwner nonReentrant {
        authorizedMap[_address] = _status;
    }

    function cancelAuthorizedAddress(
        address _address
    ) external onlyOwner nonReentrant {
        require(authorizedMap[_address], "Address is not authorized.");
        authorizedMap[_address] = false;
    }

    function isHasAuthorized(address _addr) external view returns(bool) {
        return authorizedMap[_addr];
    }

    function getUserInfo(address _user) external view returns(UserInfo memory) {
        require(_user != address(0), "user can't be zero.");
        UserInfo storage userInfo = userData[_user];
        
        return userInfo;
    }

    function balanceOf(address _user) external view returns(uint256) {
        require(_user != address(0), "user can't be zero.");
        UserInfo storage userInfo = userData[_user];
        uint256 count_balance = userInfo.count;
        return count_balance;
    }

}
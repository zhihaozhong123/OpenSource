// SPDX-License-Identifier: MIT
// Author: ZhiHao.Zhong
// Date: 2024-09-06
pragma solidity >0.6.0 <=0.8.24;

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

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external;
    function transfer(address to, uint256 value) external;
    function balanceOf(address account) external view returns (uint256);
}

contract Claim is Ownable, ReentrancyGuard {
    IERC20 public tokenContract;

    struct Receiver {
        address user;
        uint256 claimTime;
    }

    mapping(address => Receiver) private receivers;

    uint128 public fixAmounts;
    uint128 public claimCooldown = 24 hours;

    event Claimed(address indexed from, address indexed to, uint256 amount);

    constructor(address tokenContract_, uint128 fixAmounts_) Ownable(msg.sender) {
        require(tokenContract_ != address(0) && fixAmounts_ > 0,"arg can't be zero.");
        
        tokenContract = IERC20(tokenContract_);
        fixAmounts = fixAmounts_;
    }

    function claim() external nonReentrant {
        require(block.timestamp >= receivers[msg.sender].claimTime + claimCooldown, "Cooldown period has not passed.");

        receivers[msg.sender].user = msg.sender;
        receivers[msg.sender].claimTime = block.timestamp;

        tokenContract.transfer(msg.sender, fixAmounts);

        emit Claimed(address(this), msg.sender, fixAmounts);
    }

    function setFixAmounts(uint128 _fixAmounts) external onlyOwner {
        require(_fixAmounts > 0, "fix amounts must be greater than zero.");
        fixAmounts = _fixAmounts;
    }

    function setClaimCooldown(uint128 cooldown) external onlyOwner {
        claimCooldown = cooldown;
    }

    function setTokenContract(address tokenContract_) external onlyOwner {
        require(tokenContract_ != address(0), "Token address can't be zero.");
        tokenContract = IERC20(tokenContract_);
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero.");
        tokenContract.transfer(msg.sender, amount);
    }

    function balanceOf(address account) external view returns(uint256) {
        return tokenContract.balanceOf(account);
    }

    function getReceiverInfo(address user) external view returns (Receiver memory) {
        return receivers[user];
    }

    function currentTime() external view returns(uint256) {
        return block.timestamp;
    }
}
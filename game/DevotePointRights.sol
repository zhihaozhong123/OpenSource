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

interface IdevotePoint {
    function gain(
        address _user, 
        uint256 _count, 
        uint256 _kind
    ) external;

    function use(
        address _user, 
        uint256 _count, 
        uint256 _kind
    ) external;
}

interface IGenesisCrystal {
    function transferFrom(
        address from, 
        address to, 
        uint256 value
    ) external;
}

interface IAssist {
    function mint(
        address _user,
        uint256 _toolIds,
        uint256 _assistLevel,
        uint256 _growth,
        uint256 _skillLevel,
        uint256 _initTokenId
    ) external;
}

interface IPassportNFT {
    function mintBatch(
        address _user,
        uint256 _quantity,
        uint256 _initTokenId
    ) external;
}

interface IChests {
   function mintChest(
        address _user, 
        uint256 _initTokenId
    ) external;
}

contract DevotePointRights is Ownable, ReentrancyGuard{
    IdevotePoint public devotePoint;
    // IGenesisCrystal public genesisCrystalContract;
    // IAssist public assistNFTContract;
    // IPassportNFT public passportNFTContract;
    IChests public ChestsContract;

    constructor(
        address devotePoint_
        // address genesisCrystalContract_,
        // address assistNFTContract_,
        // address passportNFTContract_,
        // address ChestsContract_
    ) Ownable(msg.sender) {
        require(
            devotePoint_ != address(0),
            // genesisCrystalContract_ != address(0) &&
            // assistNFTContract_ != address(0) &&
            // passportNFTContract_ != address(0) &&
            // ChestsContract_ != address(0),
            "can not be zero"
        );
        devotePoint = IdevotePoint(devotePoint_);
        // genesisCrystalContract = IGenesisCrystal(genesisCrystalContract_);
        // assistNFTContract = IAssist(assistNFTContract_);
        // passportNFTContract = IPassportNFT(passportNFTContract_);
        // ChestsContract = IChests(ChestsContract_);
    }

    // gain
    function fangfa1(address _user, uint256 _count) external {
        uint256 _kind = 1;
        devotePoint.gain(_user, _count,  _kind);
    }

    // use
    function fangfa2(address _user, uint256 _count) external {
        uint256 _kind = 1;
        devotePoint.use(_user, _count,  _kind);
    }
}
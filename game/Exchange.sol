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

interface IGenesisCrystal {
    function transferFrom(address from, address to, uint256 value) external;
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external;
    function transfer(address to, uint256 value) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IPassportNFT {
    function transferFrom(address from, address to, uint256 value) external;
    function exists(uint256 tokenId) external view returns (bool);
}

contract Exchange is Ownable, ReentrancyGuard {
    event BuyGenesisCrystalWithTokenEvent(address indexed buyer, address indexed owner, uint256 indexed amount, uint256 genesisAmount, IERC20 tokenContract);
    event BuyGenesisCrystalWithEthEvent(address indexed buyer, address indexed owner, uint256 indexed amount, uint256 genesisAmount);
    event BuyPassportNFTWithTokenEvent(address indexed buyer, address indexed owner, uint256 indexed tokenId, uint256 amount, IERC20 tokenContract);
    event BuyPassportNFTWithETHEvent(address indexed buyer, address indexed owner, uint256 indexed tokenId, uint256 amount);

    IERC20 public tokenContract;
    IGenesisCrystal public genesisCrystalContract;
    IPassportNFT public passportNFTContract;

    uint256 private genesisExchangeTokenPrice;
    uint256 private passportExchangeTokenPrice;
    uint256 private genesisExchangeEthPrice;
    uint256 private passportExchangeEthPrice;

    modifier onlyPlayer() {
        require(msg.sender != owner(), "You can't buy for yourself");
        _;
    }

    constructor(
        address tokenContract_,
        address genesisCrystalContract_,
        address passportNFTContract_,
        uint256 genesisExchangeTokenPrice_,
        uint256 passportExchangeTokenPrice_,
        uint256 genesisExchangeEthPrice_,
        uint256 passportExchangeEthPrice_
    ) Ownable(msg.sender) {
        require(
            tokenContract_ != address(0) &&
            genesisCrystalContract_ != address(0) &&
            passportNFTContract_ != address(0),
            "arg can't be zero."
        );
        
        tokenContract = IERC20(tokenContract_);
        genesisCrystalContract = IGenesisCrystal(genesisCrystalContract_);
        passportNFTContract = IPassportNFT(passportNFTContract_);
        genesisExchangeTokenPrice = genesisExchangeTokenPrice_;
        passportExchangeTokenPrice = passportExchangeTokenPrice_;
        genesisExchangeEthPrice = genesisExchangeEthPrice_;
        passportExchangeEthPrice = passportExchangeEthPrice_;
    }

    function buyPassportWithToken(uint256 _tokenId) external onlyPlayer nonReentrant {
        _validateNFTExists(_tokenId);
        uint256 needAmount = passportExchangeTokenPrice;
        _handleTokenPayment(needAmount);
        passportNFTContract.transferFrom(owner(), msg.sender, _tokenId);
        emit BuyPassportNFTWithTokenEvent(msg.sender, owner(), _tokenId, needAmount, tokenContract);
    }

    function buyPassportWithETH(uint256 _tokenId) external payable onlyPlayer nonReentrant {
        _validateNFTExists(_tokenId);
        uint256 needAmount = passportExchangeEthPrice;
        _handleEtherPayment(needAmount);
        passportNFTContract.transferFrom(owner(), msg.sender, _tokenId);
        emit BuyPassportNFTWithETHEvent(msg.sender, owner(), _tokenId, needAmount);
    }

    function buyGenesisWithToken(uint256 _amount) external onlyPlayer nonReentrant {
        require(_amount >= 1e18, "_amount must greater than 1e18");
        uint256 needAmount = _calculatePrice(_amount, genesisExchangeTokenPrice);
        _handleTokenPayment(needAmount);
        genesisCrystalContract.transferFrom(owner(), msg.sender, _amount);
        emit BuyGenesisCrystalWithTokenEvent(msg.sender, owner(), needAmount, _amount, tokenContract);
    }

    function buyGenesisWithETH(uint256 _amount) external payable onlyPlayer nonReentrant {
        require(_amount >= 1e18, "_amount must greater than 1e18");
        uint256 needAmount = _calculatePrice(_amount, genesisExchangeEthPrice);
        _handleEtherPayment(needAmount);
        genesisCrystalContract.transferFrom(owner(), msg.sender, _amount);
        emit BuyGenesisCrystalWithEthEvent(msg.sender, owner(), needAmount, _amount);
    }

    function _validateNFTExists(uint256 tokenId) private view {
        require(passportNFTContract.exists(tokenId), "Token ID doesn't exist");
    }

    function _handleTokenPayment(uint256 needAmount) private {
        require(tokenContract.balanceOf(msg.sender) >= needAmount, "Insufficient ERC20 tokens");
        tokenContract.transferFrom(msg.sender, owner(), needAmount);
    }

    function _handleEtherPayment(uint256 needAmount) private {
        require(msg.value >= needAmount, "Insufficient ether sent");
        payable(owner()).transfer(needAmount);
    }

    function _calculatePrice(uint256 amount, uint256 price) private pure returns (uint256) {
        return (amount * price) / 1e18;
    }

    function setTokenContract(address _contract) external onlyOwner returns (bool) {
        require(_contract != address(0), "Invalid contract address.");
        tokenContract = IERC20(_contract);
        return true;
    }

    function setGenesisCrystalContract(address _contract) external onlyOwner returns (bool) {
        require(_contract != address(0), "Invalid contract address.");
        genesisCrystalContract = IGenesisCrystal(_contract);
        return true;
    }

    function setPassportNFTContract(address _contract) external onlyOwner returns (bool) {
        require(_contract != address(0), "Invalid contract address.");
        passportNFTContract = IPassportNFT(_contract);
        return true;
    }

    function setGenesisTokenPrice(uint256 _price) external onlyOwner returns (bool) {
        genesisExchangeTokenPrice = _price;
        return true;
    }

    function setPassportTokenPrice(uint256 _price) external onlyOwner returns (bool) {
        passportExchangeTokenPrice = _price;
        return true;
    }

    function setGenesisEthPrice(uint256 _price) external onlyOwner returns (bool) {
        genesisExchangeEthPrice = _price;
        return true;
    }

    function setPassportEthPrice(uint256 _price) external onlyOwner returns (bool) {
        passportExchangeEthPrice = _price;
        return true;
    }

    function getGenesisExchangeTokenPrice() external view returns (uint256) {
        return genesisExchangeTokenPrice;
    }

    function getGenesisExchangeEthPrice() external view returns (uint256) {
        return genesisExchangeEthPrice;
    }

    function getPassportExchangeTokenPrice() external view returns (uint256) {
        return passportExchangeTokenPrice;
    }

    function getPassportExchangeEthPrice() external view returns (uint256) {
        return passportExchangeEthPrice;
    }
}
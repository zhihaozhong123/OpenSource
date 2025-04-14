// SPDX-License-Identifier: MIT
// Author: ZhiHao.Zhong
// Date: 2024-09-06
pragma solidity >0.6.0 <=0.8.24;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
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
    function transfer(address to, uint256 value) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IAssists {
    function transferFrom(address from, address to, uint256 value) external;
    function ownerOf(uint256 tokienId) external view returns (address);
}

interface IChests {
    function transferFrom(address from, address to, uint256 value) external;
    function ownerOf(uint256 tokienId) external view returns (address);
}

interface IPassportNFT {
    function transferFrom(address from, address to, uint256 value) external;
    function ownerOf(uint256 tokienId) external view returns (address);
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external;
    function transfer(address to, uint256 value) external;
    function balanceOf(address account) external view returns (uint256);
}

contract MarketExchangeToken1 is Ownable, ReentrancyGuard {
    // passport
    event SellPassportNFTWithTokenEvent(address indexed seller, uint256 indexed passportNFTTokenId, uint256 indexed price, bool isListed, IERC20 tokenContract);
    event CancelSellPassportNFTWithTokenEvent(address indexed seller, uint256 indexed passportNFTTokenId, uint256 indexed price, bool isListed, IERC20 tokenContract);
    event BuyPassportNFTWithTokenEvent(address indexed buyer, address indexed seller, uint256 indexed passportNFTTokenId, uint256 price, bool isListed, IERC20 tokenContract);
    // assist
    event SellAssistNFTWithTokenEvent(address indexed seller, uint256 indexed assistNFTTokenId, uint256 indexed price, bool isListed, IERC20 tokenContract);
    event CancelSellAssistNFTWithTokenEvent( address indexed seller, uint256 indexed assistNFTTokenId, uint256 indexed price, bool isListed, IERC20 tokenContract);
    event BuyAssistNFTWithTokenEvent(address indexed buyer, address indexed seller, uint256 indexed assistNFTTokenId, uint256 price, bool isListed, IERC20 tokenContract);
    // chest
    event SellChestNFTWithTokenEvent(address indexed seller, uint256 indexed chestNFTTokenId, uint256 indexed price, bool isListed, IERC20 tokenContract);
    event CancelSellChestNFTWithTokenEvent(address indexed seller, uint256 indexed chestNFTTokenId, uint256 indexed price, bool isListed, IERC20 tokenContract);
    event BuyChestNFTWithTokenEvent(address indexed buyer, address indexed seller, uint256 indexed chestNFTTokenId, uint256 price, bool isListed, IERC20 tokenContract);
    // genesis
    event SellGenesisCrystalWithTokenEvent(address indexed seller, uint256 indexed amount, uint256 indexed price, uint256 orderId, bool isListed, IERC20 tokenContract);
    event CancelSellGenesisCrystalWithTokenEvent(address indexed seller, uint256 indexed amount, uint256 indexed price, uint256 orderId, bool isListed, IERC20 tokenContract);
    event BuyGenesisCrystalWithTokenEvent(address indexed buyer, address indexed seller, uint256 indexed amount, uint256 price, uint256 orderId, bool isListed, IERC20 tokenContract);

    IERC20 public token1;
    IGenesisCrystal public genesisCrystalContract;
    IAssists public assistNFTContract;
    IChests public chestNFTContract;
    IPassportNFT public passportNFTContract;

    uint256 public fee = 3 * 1e15;

    struct listingPassportNFT {
        address seller;
        uint256 tokenId;
        uint256 price;
        bool isListed;
    }

    struct listingAssistNFT {
        address seller;
        uint256 tokenId;
        uint256 price;
        bool isListed;
    }

    struct listingChestNFT {
        address seller;
        uint256 tokenId;
        uint256 price;
        bool isListed;
    }

    struct listingGenesis {
        address seller;
        uint256 amount;
        uint256 price;
        uint256 orderId;
        bool isListed;
    }

    mapping(address => mapping(uint256 => listingPassportNFT)) private userPassportToken1List;
    mapping(address => mapping(uint256 => listingAssistNFT)) private userAssistToken1List;
    mapping(address => mapping(uint256 => listingChestNFT)) private userChestToken1List;
    mapping(address => mapping(uint256 => listingGenesis)) private userGenesisToken1List;
    mapping(address => uint256) private userGenesisToken1Count;

    constructor(
        address token1_,
        address genesisCrystalContract_,
        address assistNFTContract_,
        address ChestNFTContract_,
        address passportNFTContract_
    ) Ownable(msg.sender) {
        require(
            genesisCrystalContract_ != address(0) &&
            assistNFTContract_ != address(0) &&
            ChestNFTContract_ != address(0) &&
            passportNFTContract_ != address(0),
            "arg can't be zero."
        );
        token1 = IERC20(token1_);
        genesisCrystalContract = IGenesisCrystal(genesisCrystalContract_);
        assistNFTContract = IAssists(assistNFTContract_);
        chestNFTContract = IChests(ChestNFTContract_);
        passportNFTContract = IPassportNFT(passportNFTContract_);
    }

    function sellPassportNFTWithToken1(uint256 _passportNFTTokenId, uint256 _token1Price) external nonReentrant {
        require(passportNFTContract.ownerOf(_passportNFTTokenId) == msg.sender, "This passport doesn't belong to you");
        require(!userPassportToken1List[msg.sender][_passportNFTTokenId].isListed, "You have already listed this passport for sale");
        require(_passportNFTTokenId > 0, "The passport tokenId can't be zero");
        require(_token1Price > 0, "The price can't be zero");

        passportNFTContract.transferFrom(msg.sender, address(this), _passportNFTTokenId);
        userPassportToken1List[msg.sender][_passportNFTTokenId] = listingPassportNFT(
            msg.sender,
            _passportNFTTokenId,
            _token1Price,
            true
        );
        emit SellPassportNFTWithTokenEvent(msg.sender, _passportNFTTokenId, _token1Price, true, token1);
    }

    function cancelSellPassportNFTWithToken1(uint256 _passportNFTTokenId) external nonReentrant {
        require(userPassportToken1List[msg.sender][_passportNFTTokenId].isListed, "Maybe this passport doesn't belong to you or it's not on sale now");
        require(_passportNFTTokenId > 0, "The passport tokenId can not be zero");

        uint256 tokenPrice = userPassportToken1List[msg.sender][_passportNFTTokenId].price;
        passportNFTContract.transferFrom(address(this), msg.sender, _passportNFTTokenId);
        delete userPassportToken1List[msg.sender][_passportNFTTokenId];
        emit CancelSellPassportNFTWithTokenEvent(msg.sender, _passportNFTTokenId, tokenPrice, false, token1);
    }

    function buyPassportNFTWithToken1(address _seller, uint256 _passportNFTTokenId) external nonReentrant {
        address seller = userPassportToken1List[_seller][_passportNFTTokenId].seller;
        uint256 price1 = userPassportToken1List[_seller][_passportNFTTokenId].price;
        bool isListed = userPassportToken1List[_seller][_passportNFTTokenId].isListed;

        uint256 sellerGet = price1 - (price1 * fee) / 1e18;
        uint256 ownerGet = (price1 * fee) / 1e18;

        require(isListed, "This passport is not on sell with token1 yet");
        require(token1.balanceOf(msg.sender) >= price1, "Insufficient token1 balance to buy passport");
        require(address(_seller) != address(0), "The seller can not be zero address");
        require(_passportNFTTokenId > 0, "The passport tokenId can not be zero");

        token1.transferFrom(msg.sender, seller, sellerGet);
        token1.transferFrom(msg.sender, owner(), ownerGet);
        passportNFTContract.transferFrom(address(this), msg.sender, _passportNFTTokenId);
        delete userPassportToken1List[_seller][_passportNFTTokenId];
        emit BuyPassportNFTWithTokenEvent(msg.sender, _seller, _passportNFTTokenId, price1, false, token1);
    }

    function sellAssistNFTWithToken1(uint256 _assistTokenId, uint256 _token1Price) external nonReentrant {
        require(assistNFTContract.ownerOf(_assistTokenId) == msg.sender, "This assist doesn't belong to you");
        require(!userAssistToken1List[msg.sender][_assistTokenId].isListed, "You have already listed this assist for sale");
        require(_assistTokenId > 0, "The assist tokenId can't be zero");
        require(_token1Price > 0, "The price can't be zero");

        assistNFTContract.transferFrom(msg.sender, address(this), _assistTokenId);
        userAssistToken1List[msg.sender][_assistTokenId] = listingAssistNFT(
            msg.sender,
            _assistTokenId,
            _token1Price,
            true
        );
        emit SellAssistNFTWithTokenEvent(msg.sender, _assistTokenId, _token1Price, true, token1);
    }

    function cancelSellAssistNFTWithToken1(uint256 _assistNFTTokenId) external nonReentrant {
        require(userAssistToken1List[msg.sender][_assistNFTTokenId].isListed, "Maybe this assist doesn't belong to you or it's not on sale now");
        require(_assistNFTTokenId > 0, "The assist tokenId can not be zero");

        uint256 tokenPrice = userAssistToken1List[msg.sender][_assistNFTTokenId].price;
        assistNFTContract.transferFrom(address(this), msg.sender, _assistNFTTokenId);
        delete userAssistToken1List[msg.sender][_assistNFTTokenId];
        emit CancelSellAssistNFTWithTokenEvent(msg.sender, _assistNFTTokenId, tokenPrice, false, token1);
    }

    function buyAssistNFTWithToken1(address _seller, uint256 _assistNFTTokenId) external nonReentrant {
        address seller = userAssistToken1List[_seller][_assistNFTTokenId].seller;
        uint256 price1 = userAssistToken1List[_seller][_assistNFTTokenId].price;
        bool isListed = userAssistToken1List[_seller][_assistNFTTokenId].isListed;

        uint256 sellerGet = price1 - (price1 * fee) / 1e18;
        uint256 ownerGet = (price1 * fee) / 1e18;

        require(isListed, "This assist is not on sell with token1 yet");
        require(token1.balanceOf(msg.sender) >= price1, "Insufficient token1 balance to buy assist");
        require(address(_seller) != address(0), "The seller can not be zero address");
        require(_assistNFTTokenId > 0, "The assist tokenId can not be zero");

        token1.transferFrom(msg.sender, seller, sellerGet);
        token1.transferFrom(msg.sender, owner(), ownerGet);
        assistNFTContract.transferFrom(address(this), msg.sender, _assistNFTTokenId);
        delete userAssistToken1List[_seller][_assistNFTTokenId];
        emit BuyAssistNFTWithTokenEvent(msg.sender, _seller, _assistNFTTokenId, price1, false, token1);
    }
    
    function sellChestNFTWithToken1(uint256 _chestTokenId, uint256 _token1Price) external nonReentrant {
        require(chestNFTContract.ownerOf(_chestTokenId) == msg.sender, "This chest doesn't belong to you" );
        require(!userChestToken1List[msg.sender][_chestTokenId].isListed, "You have already listed this chest for sale");
        require(_chestTokenId > 0, "The chest tokenId can't be zero");
        require(_token1Price > 0, "The price can't be zero");

        chestNFTContract.transferFrom(msg.sender, address(this), _chestTokenId);
        userChestToken1List[msg.sender][_chestTokenId] = listingChestNFT(
            msg.sender,
            _chestTokenId,
            _token1Price,
            true
        );
        emit SellChestNFTWithTokenEvent(msg.sender, _chestTokenId, _token1Price, true, token1);
    }

    function cancelSellChestNFTWithToken1(uint256 _chestNFTTokenId) external nonReentrant {
        require(userChestToken1List[msg.sender][_chestNFTTokenId].isListed, "Maybe this chest doesn't belong to you or it's not on sale now");
        require(_chestNFTTokenId > 0, "The chest tokenId can't be zero");

        uint256 tokenPrice = userChestToken1List[msg.sender][_chestNFTTokenId].price;
        chestNFTContract.transferFrom(address(this), msg.sender, _chestNFTTokenId);
        delete userChestToken1List[msg.sender][_chestNFTTokenId];
        emit CancelSellChestNFTWithTokenEvent(msg.sender, _chestNFTTokenId, tokenPrice, false, token1);
    }

    function buyChestNFTWithToken1(address _seller, uint256 _chestNFTTokenId) external nonReentrant {
        address seller = userChestToken1List[_seller][_chestNFTTokenId].seller;
        uint256 price1 = userChestToken1List[_seller][_chestNFTTokenId].price;
        bool isListed = userChestToken1List[_seller][_chestNFTTokenId].isListed;

        uint256 sellerGet = price1 - (price1 * fee) / 1e18;
        uint256 ownerGet = (price1 * fee) / 1e18;

        require(isListed, "This chest is not on sell with token1 yet");
        require(token1.balanceOf(msg.sender) >= price1, "Insufficient token1 balance to buy chest");
        require(address(_seller) != address(0), "The seller can't be zero address");
        require(_chestNFTTokenId > 0, "The chest tokenId can't be zero");

        token1.transferFrom(msg.sender, seller, sellerGet);
        token1.transferFrom(msg.sender, owner(), ownerGet);
        chestNFTContract.transferFrom(address(this), msg.sender, _chestNFTTokenId);
        delete userChestToken1List[_seller][_chestNFTTokenId];
        emit BuyChestNFTWithTokenEvent(msg.sender, _seller, _chestNFTTokenId, price1, false, token1);
    }

    function sellGenesisCrystalNFTWithToken1(uint256 _sellAmount, uint256 _token1Price) external nonReentrant {
        require(_sellAmount >= 1e18 && _sellAmount % 1e18 == 0 && _token1Price > 0, "The sellAmount must be greater than 0, with 18 digits of precision, and cannot be 1e18");
        require(genesisCrystalContract.balanceOf(msg.sender) >= _sellAmount, "Insufficient genesis crystals to sale");

        uint256 orderId = userGenesisToken1Count[msg.sender] + 1;
        userGenesisToken1Count[msg.sender] = orderId;
        genesisCrystalContract.transferFrom(msg.sender, address(this), _sellAmount);
        userGenesisToken1List[msg.sender][orderId] = listingGenesis(
            msg.sender,
            _sellAmount,
            _token1Price,
            orderId,
            true
        );
        emit SellGenesisCrystalWithTokenEvent(msg.sender, _sellAmount, _token1Price, orderId, true, token1);
    }

    function cancelSellGenesisCrystalNFTWithToken1(uint256 _orderId) external nonReentrant {
        require(userGenesisToken1List[msg.sender][_orderId].isListed, "Maybe this order is not belong to your, or it may not be for sale yet");

        uint256 sellAmount = userGenesisToken1List[msg.sender][_orderId].amount;
        uint256 tokenPrice = userGenesisToken1List[msg.sender][_orderId].price;

        genesisCrystalContract.transfer(msg.sender, sellAmount);
        delete userGenesisToken1List[msg.sender][_orderId];
        emit CancelSellGenesisCrystalWithTokenEvent(msg.sender, sellAmount, tokenPrice, _orderId, false, token1);
    }

    function buyGenesisCrystalWithToken1(address _seller, uint256 _orderId, uint256 _buyAmount) external nonReentrant {
        require(msg.sender != _seller, "You can't buy your own pending order");
        require(userGenesisToken1List[_seller][_orderId].isListed, "Genesis are not on sell with token1 yet");
        require(_buyAmount <= userGenesisToken1List[_seller][_orderId].amount, "Purchase amount cannot exceed available quantity");

        uint256 totalPrice = (userGenesisToken1List[_seller][_orderId].price * _buyAmount) / 1e18;
        uint256 ownerGet = (totalPrice * fee) / 1e18;
        uint256 sellerGet = totalPrice - (ownerGet);

        require(token1.balanceOf(msg.sender) >= totalPrice, "Insufficient token balance");

        token1.transferFrom(msg.sender, _seller, sellerGet);
        token1.transferFrom(msg.sender, owner(), ownerGet);
        genesisCrystalContract.transfer(msg.sender, _buyAmount);

        userGenesisToken1List[_seller][_orderId].amount -= _buyAmount;

        if (userGenesisToken1List[_seller][_orderId].amount == 0) {
            delete userGenesisToken1List[msg.sender][_orderId];
            emit BuyGenesisCrystalWithTokenEvent(msg.sender, _seller, _buyAmount, userGenesisToken1List[_seller][_orderId].price, _orderId, false, token1);
        } else {
            emit BuyGenesisCrystalWithTokenEvent(msg.sender, _seller, _buyAmount, userGenesisToken1List[_seller][_orderId].price, _orderId, true, token1);
        }
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function setToken1(address _contract) external onlyOwner {
        require(_contract != address(0), "The arg can't be zero.");
        token1 = IERC20(_contract);
    }

    function setAssistContract(address _contract) external onlyOwner {
        require(_contract != address(0), "Invalid contract address.");
        assistNFTContract = IAssists(_contract);
    }

    function setChestContract(address _contract) external onlyOwner {
        require(_contract != address(0), "Invalid contract address.");
        chestNFTContract = IChests(_contract);
    }

    function setGenesisCrystalContract(address _contract) external {
        require(_contract != address(0), "Invalid contract address.");
        genesisCrystalContract = IGenesisCrystal(_contract);
    }

    function setPassportNFTContract(address _contract) external onlyOwner {
        require(_contract != address(0), "Invalid contract address.");
        passportNFTContract = IPassportNFT(_contract);
    }

    function WithdrawToken1(uint256 amount) external onlyOwner nonReentrant returns (bool) {
        require(amount > 0, "Withdraw amount must be greater than zero");
        token1.transfer(owner(), amount);
        return true;
    }

    function getUserPassportToken1List(address _user, uint256 _tokenId) external view returns (address seller, uint256 tokenId, uint256 price, bool isListed) {
        listingPassportNFT memory listing = userPassportToken1List[_user][_tokenId];
        return (listing.seller, listing.tokenId, listing.price, listing.isListed);
    }

    function getUserAssistToken1List(address _user, uint256 _tokenId) external view returns (address seller, uint256 tokenId, uint256 price, bool isListed) {
        listingAssistNFT memory listing = userAssistToken1List[_user][_tokenId];
        return (listing.seller, listing.tokenId, listing.price, listing.isListed);
    }

   function getUserChestToken1List(address _user, uint256 _tokenId) external view returns (address seller, uint256 tokenId, uint256 price, bool isListed) {
        listingChestNFT memory listing = userChestToken1List[_user][_tokenId];
        return (listing.seller, listing.tokenId, listing.price, listing.isListed);
    }

    function getUserGenesisToken1List(address _user, uint256 _orderId) external view returns (address seller, uint256 amount, uint256 price, uint256 orderId, bool isListed) {
        listingGenesis memory listing = userGenesisToken1List[_user][_orderId];
        if (listing.isListed && listing.amount > 0) {
            return (listing.seller, listing.amount, listing.price, listing.orderId, true);
        } else {
            return (address(0), 0, 0, 0, false);
        }
    }

    function queryPassportSeller(uint256 _tokenId) external view returns (address) {
        listingPassportNFT memory listing = userPassportToken1List[address(passportNFTContract)][_tokenId];
        require(listing.isListed, "NFT is not listed for sale");
        return listing.seller;
    }
}
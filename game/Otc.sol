// SPDX-License-Identifier: MIT
// Author: ZhiHao.Zhong
// Date: 2024-09-06
pragma solidity >0.6.0 <=0.8.24;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface INTCoin is IERC20 {
    function burn(uint256 amount) external;
}

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IGenesisCrystal {
    function transferFrom(address from, address to, uint256 value) external;
    function balanceOf(address _user) external view returns (uint256);
}

contract OTC is Ownable, ReentrancyGuard {
    IGenesisCrystal public genesisCrystalContract;
    IERC20 public wethContract;

    uint256 public fee = 3 * 1e15;

    constructor(
        address genesisCrystalContract_,
        IERC20 wethContract_
        ) Ownable(msg.sender) {
        genesisCrystalContract = IGenesisCrystal(genesisCrystalContract_);
        wethContract = IERC20(wethContract_);
    }

    struct Purchaser {
        uint256 orderId;
        address purchaser;
        uint256 orderAmounts;
        uint256 orderPrice;
        uint256 remainedOrderGenesisAmounts;
        uint256 hasDealedOrderAmounts;
        uint256 fixPayReserve;
        uint256 remainedOrderWethAmounts;
        uint256 hasPayedWethAmounts;
        uint256 orderPurchaseTime;
        uint256 orderRevokeTime;
        bool isRevoked;
        bool isFinished;
    }

    mapping(address => uint256) private orderIdMap;
    mapping(uint256 => mapping(address=>address)) private orderIdToMap;
    mapping(address => mapping(uint256 => bool)) private isRevokedMap;
    mapping(address => mapping(uint256 => Purchaser)) private PurchaseMap;
    mapping(address => mapping(uint256 => bool)) private orderIdExists;

    event PurchaseEvent(
        uint256 indexed orderId,
        address indexed purchaser,
        uint256 indexed orderAmounts,
        uint256 orderPrice,
        uint256 remainedOrderGenesisAmounts,
        uint256 hasDealedOrderAmounts,
        uint256 fixPayReserve,
        uint256 remainedOrderWethAmounts,
        uint256 hasPayedWethAmounts,
        uint256 orderPurchaseTime,
        bool isRevoked,
        bool isFinished
    );

    event RevokeEvent(
        uint256 indexed orderId,
        address indexed purchaser,
        uint256 indexed orderAmounts,
        uint256 orderPrice,
        uint256 remainedOrderGenesisAmounts,
        uint256 hasDealedOrderAmounts,
        uint256 fixPayReserve,
        uint256 remainedOrderWethAmounts,
        uint256 hasPayedWethAmounts,
        uint256 orderPurchaseTime,
        bool isRevoked,
        bool isFinished
    );

    event DealEvent(
        uint256 indexed orderId,
        address indexed purchaser,
        address indexed trader,
        uint256 genesisAmountsSell,
        uint256 remainedOrderGenesisAmounts,
        uint256 hasDealedOrderAmounts,
        uint256 fixPayReserve,
        uint256 remainedOrderWethAmounts,
        uint256 hasPayedWethAmounts,
        bool isRevoked,
        bool isFinished
    );

    function Purchase(uint256 _genesisAmounts, uint256 _wethPrice) external nonReentrant {
        require(_genesisAmounts >= 100 * 1e18 && _genesisAmounts % 1e18 == 0, "genesis amounts must be greater than 100 and must be an integer");
        require(_wethPrice >= 5e13, "WETH price must be at least 0.00005");
        uint256 extraDigit = _wethPrice % 1e13;
        require(extraDigit == 0 || (extraDigit >= 1e12 && extraDigit < 1e13 && extraDigit % 1e12 == 0), "WETH price must have at most one additional digit after 0.00005");

        uint256 prePayReserve = _genesisAmounts * _wethPrice / 1e18;
        uint256 order = orderIdMap[msg.sender] + 1;
        uint256 remainedOrderGenesisAmounts = _genesisAmounts;
        uint256 remainedOrderWethAmounts = prePayReserve;

        Purchaser storage purchaser = PurchaseMap[msg.sender][order];

        require(wethContract.allowance(msg.sender, address(this)) >= prePayReserve, "Insufficient allowance");
        require(wethContract.balanceOf(msg.sender) >= prePayReserve, "Insufficient WETH balance");

        wethContract.transferFrom(msg.sender, address(this), prePayReserve);
        
        orderIdMap[msg.sender] = order;
        orderIdToMap[order][msg.sender] = msg.sender;
        isRevokedMap[msg.sender][order] = false;
        orderIdExists[msg.sender][order] = true;

        purchaser.orderId = order;
        purchaser.purchaser = msg.sender;
        purchaser.orderAmounts = _genesisAmounts;
        purchaser.orderPrice = _wethPrice;
        purchaser.remainedOrderGenesisAmounts = remainedOrderGenesisAmounts;
        purchaser.fixPayReserve = prePayReserve;
        purchaser.remainedOrderWethAmounts = remainedOrderWethAmounts;
        purchaser.orderPurchaseTime = block.timestamp;
        purchaser.isRevoked = false;

        emit PurchaseEvent(
            purchaser.orderId,
            purchaser.purchaser,
            purchaser.orderAmounts,
            purchaser.orderPrice,
            purchaser.remainedOrderGenesisAmounts,
            purchaser.hasDealedOrderAmounts,
            purchaser.fixPayReserve,
            purchaser.remainedOrderWethAmounts,
            purchaser.hasPayedWethAmounts,
            purchaser.orderPurchaseTime,
            purchaser.isRevoked,
            purchaser.isFinished
        );
    }

    function revoke(address user, uint256 order) external nonReentrant {
        Purchaser storage purchaser = PurchaseMap[user][order];
        address currentUser = orderIdToMap[order][user];
        uint256 remainedOrderGenesisAmounts = purchaser.remainedOrderGenesisAmounts;
        uint256 remainedOrderWethAmounts = purchaser.remainedOrderWethAmounts;

        require(orderIdExists[user][order] == true, "this order doesn't exist or not belong to you");
        require(currentUser == msg.sender, "you haven't own this order");
        require(isRevokedMap[user][order] == false, "this order has been revoked before");
        require(remainedOrderGenesisAmounts != 0, "this order has finished");

        wethContract.transfer(user, remainedOrderWethAmounts);

        purchaser.orderId = order;
        purchaser.purchaser = user;
        purchaser.orderRevokeTime = block.timestamp;
        purchaser.isRevoked = true;
        purchaser.isFinished = false;

        isRevokedMap[user][order] = true;
        orderIdExists[user][order] = false; 

        emit RevokeEvent(
            purchaser.orderId,
            purchaser.purchaser,
            purchaser.orderAmounts,
            purchaser.orderPrice,
            purchaser.remainedOrderGenesisAmounts,
            purchaser.hasDealedOrderAmounts,
            purchaser.fixPayReserve,
            purchaser.remainedOrderWethAmounts,
            purchaser.hasPayedWethAmounts,
            purchaser.orderPurchaseTime,
            purchaser.isRevoked,
            purchaser.isFinished
        );
    }

    function deal(address user, uint256 order, uint256 genesisAmountsSell) external nonReentrant {
        Purchaser storage purchaser = PurchaseMap[user][order];

        require(msg.sender != user,"deal for your own order is forbidden");
        require(orderIdExists[user][order] == true, "this order doesn't exist or not belong to the user");
        require(purchaser.isFinished == false, "the order has been revoked or finished");
        require(genesisAmountsSell >= 1e18 && genesisAmountsSell % 1e18 == 0, "The number of genesis deal must be greater than 1e18 and must be an integer");
        require(genesisAmountsSell <= purchaser.remainedOrderGenesisAmounts,"cannot be greater than the number requested");

        uint256 wethPrice = purchaser.orderPrice;
        uint256 wethNeeded = genesisAmountsSell * wethPrice / 1e18;
        uint256 sellerGet = wethNeeded - (wethNeeded * fee) / 1e18;
        uint256 ownerGet = (wethNeeded * fee) / 1e18;

        genesisCrystalContract.transferFrom(msg.sender, user, genesisAmountsSell);
        wethContract.transfer(msg.sender, sellerGet);
        wethContract.transfer(owner(), ownerGet);

        isRevokedMap[user][order] = false;

        purchaser.remainedOrderGenesisAmounts -= genesisAmountsSell;
        purchaser.hasDealedOrderAmounts += genesisAmountsSell;
        purchaser.remainedOrderWethAmounts -= wethNeeded;
        purchaser.hasPayedWethAmounts += wethNeeded;
        purchaser.isRevoked = false;

        if (purchaser.remainedOrderGenesisAmounts == 0) {
            purchaser.isFinished = true;
            orderIdExists[user][order] = false;
        } else {
            purchaser.isFinished = false;
        }

        emit DealEvent(
            purchaser.orderId,
            purchaser.purchaser,
            msg.sender,
            genesisAmountsSell,
            purchaser.remainedOrderGenesisAmounts,
            purchaser.hasDealedOrderAmounts,
            purchaser.fixPayReserve,
            purchaser.remainedOrderWethAmounts,
            purchaser.hasPayedWethAmounts,
            purchaser.isRevoked,
            purchaser.isFinished
        );
    }

    function setFee(uint256 _fee) onlyOwner nonReentrant external {
        fee = _fee;
    }

    function purchaseInfo(address user, uint256 order) external view returns(Purchaser memory) {
        Purchaser storage purchaser = PurchaseMap[user][order];

        return Purchaser({
            orderId: purchaser.orderId,
            purchaser: purchaser.purchaser,
            orderAmounts: purchaser.orderAmounts,
            orderPrice: purchaser.orderPrice,
            remainedOrderGenesisAmounts: purchaser.remainedOrderGenesisAmounts,
            hasDealedOrderAmounts: purchaser.hasDealedOrderAmounts,
            fixPayReserve: purchaser.fixPayReserve,
            remainedOrderWethAmounts: purchaser.remainedOrderWethAmounts,
            hasPayedWethAmounts: purchaser.hasPayedWethAmounts,
            orderPurchaseTime: purchaser.orderPurchaseTime,
            orderRevokeTime: purchaser.orderRevokeTime,
            isRevoked: purchaser.isRevoked,
            isFinished: purchaser.isFinished
        }); 
    }

    function WithdrawToken(uint256 amount) external onlyOwner nonReentrant returns (bool) {
        require(amount > 0, "Withdraw amount must be greater than zero");
        wethContract.transfer(owner(), amount);
        return true;
    }

    function isRevoked(address user, uint256 order) external view returns(bool) {
        require(address(user) != address(0),"invalid user account");
        require(uint256(order) > 0,"the order can't be zero");
        return isRevokedMap[user][order];
    }

    function isExists(address user, uint256 order) external view returns(bool) {
        require(address(user) != address(0),"invalid user account");
        require(uint256(order) > 0,"the order can't be zero");
        return orderIdExists[user][order];
    }

    function setGenesisCrystalContract(address _contract) external onlyOwner returns (bool) {
        require(_contract != address(0), "Invalid contract address");
        genesisCrystalContract = IGenesisCrystal(_contract);
        return true;
    }

    function setWethContract(IERC20 _contract) external onlyOwner returns (bool) {
        wethContract = IERC20(_contract);
        return true;
    }
}
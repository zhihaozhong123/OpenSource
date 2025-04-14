// SPDX-License-Identifier: MIT
// Author: ZhiHao.Zhong
// Date: 2024-09-06
pragma solidity >0.6.0 <=0.8.24;

library Counters {
    struct Counter {
        uint256 _value;
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        counter._value += 1;
    }
}

library Math {
    enum Rounding {
        Floor,
        Ceil,
        Trunc,
        Expand
    }

    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    function log10(
        uint256 value,
        Rounding rounding
    ) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return
                result +
                (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
        }
    }

    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    function log256(
        uint256 value,
        Rounding rounding
    ) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return
                result +
                (
                    unsignedRoundsUp(rounding) && 1 << (result << 3) < value
                        ? 1
                        : 0
                );
        }
    }

    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}

library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 20;

    error StringsInsufficientHexLength(uint256 value, uint256 length);

    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    function toHexString(
        uint256 value,
        uint256 length
    ) internal pure returns (string memory) {
        uint256 localValue = value;
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = HEX_DIGITS[localValue & 0xf];
            localValue >>= 4;
        }
        if (localValue != 0) {
            revert StringsInsufficientHexLength(value, length);
        }
        return string(buffer);
    }

    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), ADDRESS_LENGTH);
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

interface IERC721Errors {
    error ERC721InvalidOwner(address owner);
    error ERC721NonexistentToken(uint256 tokenId);
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);
    error ERC721InvalidSender(address sender);
    error ERC721InvalidReceiver(address receiver);
    error ERC721InsufficientApproval(address operator, uint256 tokenId);
    error ERC721InvalidApprover(address approver);
    error ERC721InvalidOperator(address operator);
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
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
    function balanceOf(address _user) external view returns (uint256);
}

contract PassportNFT is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private _tokenIdTracker;

    event Mint(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );
    event ApproveLevel(
        address indexed from,
        uint256 indexed levelcount,
        uint256 indexed passportTokenId
    );
    event DecreaseLevel(
        address indexed from,
        uint256 indexed levelcount,
        uint256 indexed passportTokenId
    );
    event Transfer(
        address indexed from, 
        address indexed to, 
        uint256 value
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event BatchApproval(
        address indexed owner,
        address indexed spender,
        uint256[] value
    );
    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    IGenesisCrystal public genesis_crystal;

    string public constant name = "Passport";
    string public constant symbol = "POT";
    string public baseTokenURI = "https://ivory-worrying-seahorse-252.mypinata.cloud/ipfs/bafybeid7feiprgqq32lp6l24xmorl3ygh3bqe7jyzt7mvo5rphekurdqaa/";
    string public constant baseExtension = ".json";

    uint256 private _total;
    uint128 public constant TOTAL_TOKENID = 9999;
    uint64 public constant MAX_TOTAL_LIMIT = 50_000;
    uint16 public constant MAX_LEVEL = 34;

    uint256[34] incrArr = [
        0,
        20,
        50,
        90,
        150,
        230,
        350,
        510,
        750,
        1070,
        1550,
        2190,
        3150,
        4430,
        6350,
        8910,
        12750,
        17870,
        25550,
        35790,
        51150,
        71630,
        102350,
        143310,
        204750,
        286670,
        409550,
        573390,
        819150,
        1146830,
        1638350,
        2293710,
        3276750,
        4587470
    ];

    error errMsg(string message);

    mapping(address => uint256[]) private _userTokens;
    mapping(uint256 => address) private _tokenOwners;
    mapping(address => mapping(uint256 => uint256)) private _passportLevels;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => address) private _owners;
    mapping(uint256 => mapping(uint256 => uint256)) private bind;
    mapping(address => bool) private authorizedMap;

    modifier onlyAuthorized() {
        require(
            authorizedMap[msg.sender] || msg.sender == owner(),
            "Not authorized, or only owner can call."
        );
        _;
    }

    constructor(address genesis_crystal_) Ownable(msg.sender) {
        require(
            genesis_crystal_ != address(0),
            "arg can't be zero."
        );
        
        genesis_crystal = IGenesisCrystal(genesis_crystal_);
    }

    function mintBatch(
        address _user,
        uint256 quantity,
        uint256 _initTokenId
    ) external onlyAuthorized nonReentrant {
        require(_user != address(0), "Invalid user address");
        require(quantity > 0, "Quantity must be greater than zero");

        if (_user == owner()) {
            require(
                quantity <= TOTAL_TOKENID - bind[_initTokenId][TOTAL_TOKENID],
                "Token ID exceeds limit"
            );
        } else {
            require(
                quantity == 1,
                "Non-owner can only mint one token at a time"
            );
        }

        uint256 startTokenId = _initTokenId + bind[_initTokenId][TOTAL_TOKENID];

        require(
            startTokenId + quantity <= _initTokenId + TOTAL_TOKENID,
            "Token ID exceeds limit"
        );
        require(
            _total + quantity <= MAX_TOTAL_LIMIT,
            "Total supply exceeds max limit"
        );

        for (uint256 i = 1; i <= quantity; i++) {
            uint256 _tokenId = startTokenId + i;
            require(
                _total < MAX_TOTAL_LIMIT,
                "The total supply exceeds the max limit"
            );

            _mint(_user, _tokenId);
            _tokenIdTracker.increment();
            _total += 1;
            _userTokens[_user].push(_tokenId);
            _passportLevels[_user][_tokenId] = 1;

            emit Mint(address(0), _user, _tokenId);
        }

        bind[_initTokenId][TOTAL_TOKENID] += quantity;
    }

    function approveLevel(
        uint256 levelCount,
        uint256 passportTokenId
    ) external nonReentrant {
        if (msg.sender == owner()) {
            revert errMsg("Deployer is not allowed to operate");
        }

        if (_userTokens[msg.sender].length <= 0) {
            revert errMsg("You must own at least one passport token");
        }

        if (levelCount == _passportLevels[msg.sender][passportTokenId]) {
            revert errMsg("You cannot approve to the current level");
        }

        if (msg.sender != ownerOf(passportTokenId)) {
            revert errMsg("You are not the owner of this passport token");
        }

        if (levelCount < _passportLevels[msg.sender][passportTokenId]) {
            revert errMsg("the level you approve less than your current level is not allowed");
        }

        if (levelCount > MAX_LEVEL) {
            revert errMsg("Levelcount exceeds the maximum level limit");
        }

        uint256 calulateResult = incrArr[levelCount - 1] - incrArr[_passportLevels[msg.sender][passportTokenId] - 1];
        uint256 requiredTokens = calulateResult * 1e18;
        uint256 userBalance = genesis_crystal.balanceOf(msg.sender);

        if (userBalance < requiredTokens) {
            revert errMsg("Insufficient tokens for leveling up");
        }

        genesis_crystal.transferFrom(msg.sender, owner(), requiredTokens);
        _passportLevels[msg.sender][passportTokenId] = levelCount;

        emit ApproveLevel(msg.sender, levelCount, passportTokenId);
    }

    function decreaseLevel(
        uint256 levelCount,
        uint256 passportTokenId
    ) external nonReentrant {
        if (msg.sender == owner()) {
            revert errMsg("the deployer is not allowd to operate");
        }

        if (msg.sender != ownerOf(passportTokenId)) {
            revert errMsg("You are not the owner of this passport token");
        }

        if (_userTokens[msg.sender].length <= 0) {
            revert errMsg("You must own at least one passport token");
        }

        uint256 currentLevel = _passportLevels[msg.sender][passportTokenId];

        if (levelCount == _passportLevels[msg.sender][passportTokenId]) {
            revert errMsg("You cannot downgrade to the current level");
        }

        if (_passportLevels[msg.sender][passportTokenId] <= 1) {
            revert errMsg("The token level is already at the lowest level");
        }

        if (levelCount == 0) {
            revert errMsg("The level cannot be lower than zero");
        }

        uint256 calulateResult = ((incrArr[currentLevel - 1] - incrArr[levelCount - 1]) * 99) / 100;
        uint256 requiredTokens = calulateResult * 1e18;

        genesis_crystal.transferFrom(owner(), msg.sender, requiredTokens);
        _passportLevels[msg.sender][passportTokenId] = levelCount;

        emit DecreaseLevel(msg.sender, levelCount, passportTokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external nonReentrant returns (bool) {
        if (to == address(0)) {
            revert IERC721Errors.ERC721InvalidReceiver(to);
        }

        if (!_isAuthorized(from, msg.sender, tokenId)) {
            revert IERC721Errors.ERC721InsufficientApproval(
                msg.sender,
                tokenId
            );
        }

        if (ownerOf(tokenId) != from) {
            revert IERC721Errors.ERC721IncorrectOwner(
                from,
                tokenId,
                ownerOf(tokenId)
            );
        }

        _transfer(from, to, tokenId);

        return true;
    }

    function _transfer(address from, address to, uint256 tokenId) private {
        _balances[from] -= 1;
        _balances[to] += 1;

        _owners[tokenId] = to;
        _tokenOwners[tokenId] = to;

        _removeTokenFromOwnerEnumeration(from, tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);
        _updatePassportOwnership(from, to, tokenId);

        emit Transfer(from, to, tokenId);
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

    function setGenesisCrystalContract(
        address _contract
    ) external onlyOwner nonReentrant {
        require(_contract != address(0), "Invalid contract address");
        genesis_crystal = IGenesisCrystal(_contract);
    }

    function getLevelByUserAndPid(
        address user,
        uint256 _passportTokenId
    ) external view returns (uint256) {
        if (!userHasPassportToken(user, _passportTokenId)) {
            revert IERC721Errors.ERC721NonexistentToken(_passportTokenId);
        }

        return _passportLevels[user][_passportTokenId];
    }

    function updateBaseTokenURI(
        string memory newBaseTokenURI
    ) external onlyOwner {
        baseTokenURI = newBaseTokenURI;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(exists(tokenId), "Token ID does not exist");
        uint256 temp = tokenId - (tokenId % (10 ** (Math.log10(tokenId) - 1)));

        return
            string(
                abi.encodePacked(baseTokenURI, temp.toString(), baseExtension)
            );
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        return _requireOwned(tokenId);
    }

    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) {
            revert IERC721Errors.ERC721InvalidOwner(address(0));
        }
        return _balances[owner];
    }

    function totalSupply() external view returns (uint256) {
        return _total;
    }

    function _mint(address to, uint256 tokenId) private {
        address previousOwner = _update(to, tokenId, address(0));

        if (to == address(0)) {
            revert IERC721Errors.ERC721InvalidReceiver(address(0));
        }

        if (previousOwner != address(0)) {
            revert IERC721Errors.ERC721InvalidSender(address(0));
        }
    }

    function userHasPassportToken(
        address user,
        uint256 passportTokenId
    ) public view returns (bool) {
        for (uint256 i = 0; i < _userTokens[user].length; i++) {
            if (_userTokens[user][i] == passportTokenId) {
                return true;
            }
        }

        return false;
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function isHasAuthorized(address _addr) external view returns(bool) {
        return authorizedMap[_addr];
    }

    function _checkAuthorized(
        address owner,
        address spender,
        uint256 tokenId
    ) private view {
        if (!_isAuthorized(owner, spender, tokenId)) {
            if (owner == address(0)) {
                revert IERC721Errors.ERC721NonexistentToken(tokenId);
            } else {
                revert IERC721Errors.ERC721InsufficientApproval(
                    spender,
                    tokenId
                );
            }
        }
    }

    function _isAuthorized(
        address owner,
        address spender,
        uint256 tokenId
    ) private view returns (bool) {
        return
            spender != address(0) &&
            (owner == spender ||
                isApprovedForAll(owner, spender) ||
                _getApproved(tokenId) == spender);
    }

    function _ownerOf(uint256 tokenId) private view returns (address) {
        return _owners[tokenId];
    }

    function _requireOwned(uint256 tokenId) private view returns (address) {
        address owner = _ownerOf(tokenId);
        if (owner == address(0)) {
            revert IERC721Errors.ERC721NonexistentToken(tokenId);
        }
        return owner;
    }

    function _approve(
        address to,
        uint256 tokenId,
        address auth,
        bool emitEvent
    ) private {
        if (emitEvent || auth != address(0)) {
            address owner = _requireOwned(tokenId);

            if (
                auth != address(0) &&
                owner != auth &&
                !isApprovedForAll(owner, auth)
            ) {
                revert IERC721Errors.ERC721InvalidApprover(auth);
            }

            if (emitEvent) {
                emit Approval(owner, to, tokenId);
            }
        }

        _tokenApprovals[tokenId] = to;
    }

    function _getApproved(uint256 tokenId) private view returns (address) {
        return _tokenApprovals[tokenId];
    }

    function _updatePassportOwnership(
        address from,
        address to,
        uint256 tokenId
    ) private {
        _passportLevels[to][tokenId] = _passportLevels[from][tokenId];
        delete _passportLevels[from][tokenId];
    }

   function _update(address to, uint256 tokenId, address auth) private returns (address) {
        address from = _ownerOf(tokenId);

        if (auth != address(0)) {
            _checkAuthorized(from, auth, tokenId);
        }

        if (from != address(0)) {
            _approve(address(0), tokenId, address(0), false);

            unchecked {
                _balances[from] -= 1;
            }
        }

        if (to != address(0)) {
            unchecked {
                _balances[to] += 1;
            }   
        }

        _owners[tokenId] = to;

        return from;
    }

    function _removeTokenFromOwnerEnumeration(
        address from,
        uint256 tokenId
    ) private {
        uint256 length = _userTokens[from].length;
        uint256 tokenIndex = _findTokenIndex(from, tokenId);

        if (tokenIndex < length - 1) {
            _userTokens[from][tokenIndex] = _userTokens[from][length - 1];
        }

        _userTokens[from].pop();
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        _userTokens[to].push(tokenId);
    }

    function _findTokenIndex(
        address owner,
        uint256 tokenId
    ) private view returns (uint256) {
        uint256 length = _userTokens[owner].length;
        for (uint256 i = 0; i < length; i++) {
            if (_userTokens[owner][i] == tokenId) {
                return i;
            }
        }
        revert IERC721Errors.ERC721NonexistentToken(tokenId);
    }

    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            msg.sender == owner || isApprovedForAll(owner, msg.sender),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function batchApprove(address to, uint256[] calldata tokenIds) external {
        require(to != address(0), "ERC721: approve to the zero address");
        
        address owner;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            owner = ownerOf(tokenId);
            require(to != owner, "ERC721: approval to current owner");

            require(
                msg.sender == owner || isApprovedForAll(owner, msg.sender),
                "ERC721: approve caller is not owner nor approved for all"
            );

            _tokenApprovals[tokenId] = to;

            emit Approval(owner, to, tokenId);
        }

        emit BatchApproval(owner, to, tokenIds);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender, "ERC721: approve to caller");

        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }
}

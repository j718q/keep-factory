// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import "@lukso/lsp7-contracts/contracts/presets/LSP7Mintable.sol";
import "@lukso/lsp7-contracts/contracts/LSP7DigitalAsset.sol";
import "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

interface ILSP26FollowerSystem {
    function isFollowing(address follower, address addr) external view returns (bool);
}

address constant FOLLOWER_SYSTEM = 0xf01103E5a9909Fc0DBe8166dA7085e0285daDDcA;

contract MembershipClaim is LSP7Mintable {
    mapping(address => bool) private _claimed;
    bool private immutable _transferable;
    bool private immutable _revocable;
    bytes32 private immutable _codeHash;
    uint256 private immutable _claimFrom;
    uint256 private immutable _claimUntil;
    uint256 private immutable _maxClaims;
    bool private immutable _mustFollow;
    bool private immutable _closable;
    address private immutable _followed;
    uint256 private _claims;
    bool private _closed;
    bool private _locked;
    address[] private _holders;
    mapping(address => bool) private _seen;

    error AlreadyClaimed();
    error MintDisabled();
    error NonTransferable();
    error WrongCode();
    error NotRevocable();
    error NotAllowed();
    error ClaimEnded();
    error NotFollowing();
    error NotStarted();
    error CapReached();
    error NotClosable();

    mapping(address => bool) private _admins;
    address private immutable _factory;

    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        bool transferable_,
        bool revocable_,
        bytes32 codeHash_,
        uint256 claimFrom_,
        uint256 claimUntil_,
        uint256 maxClaims_,
        bool mustFollow_,
        bool closable_,
        address factory_
    ) LSP7Mintable(name_, symbol_, owner_, 0, true) {
        _transferable = transferable_;
        _revocable = revocable_;
        _codeHash = codeHash_;
        _claimFrom = claimFrom_;
        _claimUntil = claimUntil_;
        _maxClaims = maxClaims_;
        _mustFollow = mustFollow_;
        _closable = closable_;
        _followed = owner_;
        _factory = factory_;
    }

    function mint(address, uint256, bool, bytes memory) public override {
        revert MintDisabled();
    }

    function claim(string calldata code) external {
        if (_closed) revert ClaimEnded();
        if (_claimFrom != 0 && block.timestamp < _claimFrom) revert NotStarted();
        if (_claimUntil != 0 && block.timestamp > _claimUntil) revert ClaimEnded();
        if (_maxClaims != 0 && _claims >= _maxClaims) revert CapReached();
        if (_mustFollow && !ILSP26FollowerSystem(FOLLOWER_SYSTEM).isFollowing(msg.sender, _followed)) {
            revert NotFollowing();
        }
        if (_codeHash != bytes32(0) && keccak256(bytes(code)) != _codeHash) revert WrongCode();
        if (_claimed[msg.sender]) revert AlreadyClaimed();
        _claimed[msg.sender] = true;
        _claims += 1;
        _remember(msg.sender);
        if (_locked) revert NotAllowed();
        _locked = true;
        _mint(msg.sender, 1, true, "");
        _locked = false;
    }

    function revokeUnfollowers(uint256 start) external returns (uint256 burned) {
        if (!_mustFollow || !_revocable || (msg.sender != owner() && !_admins[msg.sender])) revert NotRevocable();
        if (_locked) revert NotAllowed();
        _locked = true;
        uint256 end = start + 40;
        if (end > _holders.length) end = _holders.length;
        for (uint256 i = start; i < end; ) {
            address account = _holders[i];
            uint256 balance = balanceOf(account);
            if (balance > 0 && !ILSP26FollowerSystem(FOLLOWER_SYSTEM).isFollowing(account, _followed)) {
                try this.burn(account, balance, "") {
                    burned += 1;
                } catch {}
            }
            unchecked { ++i; }
        }
        _locked = false;
    }

    function holderCount() external view returns (uint256) {
        return _holders.length;
    }

    function _remember(address account) private {
        if (account == address(0) || _seen[account]) return;
        _seen[account] = true;
        _holders.push(account);
    }

    function close() external {
        if (!_closable || msg.sender != owner()) revert NotClosable();
        _closed = true;
    }

    function codeHash() external view returns (bytes32) {
        return _codeHash;
    }

    function hasClaimed(address account) external view returns (bool) {
        return _claimed[account];
    }

    function transferable() external view returns (bool) {
        return _transferable;
    }

    function revocable() external view returns (bool) {
        return _revocable;
    }

    function claimUntil() external view returns (uint256) {
        return _claimUntil;
    }

    function claimFrom() external view returns (uint256) {
        return _claimFrom;
    }

    function maxClaims() external view returns (uint256) {
        return _maxClaims;
    }

    function claims() external view returns (uint256) {
        return _claims;
    }

    function closable() external view returns (bool) {
        return _closable;
    }

    function closed() external view returns (bool) {
        return _closed;
    }

    function mustFollow() external view returns (bool) {
        return _mustFollow;
    }

    function followed() external view returns (address) {
        return _followed;
    }

    function isAdmin(address account) external view returns (bool) {
        return _admins[account];
    }

    function setAdmin(address account, bool allowed) external {
        if (msg.sender != owner() && msg.sender != _factory) revert NotAllowed();
        if (account == address(0) || account == owner()) revert NotAllowed();
        _admins[account] = allowed;
    }

    function burn(address from, uint256 amount, bytes memory data) public {
        if (!_revocable || (msg.sender != owner() && !_admins[msg.sender] && !(msg.sender == address(this) && _locked))) {
            revert NotRevocable();
        }
        _burn(from, amount, data);
    }

    function transfer(address from, address to, uint256 amount, bool force, bytes memory data)
        public
        override(ILSP7DigitalAsset, LSP7DigitalAsset)
    {
        if (!_transferable) revert NonTransferable();
        _remember(to);
        super.transfer(from, to, amount, force, data);
    }

    function transferBatch(
        address[] memory from,
        address[] memory to,
        uint256[] memory amount,
        bool[] memory force,
        bytes[] memory data
    ) public override(ILSP7DigitalAsset, LSP7DigitalAsset) {
        if (!_transferable) revert NonTransferable();
        for (uint256 i = 0; i < to.length; ) {
            _remember(to[i]);
            unchecked { ++i; }
        }
        super.transferBatch(from, to, amount, force, data);
    }

    function authorizeOperator(address operator, uint256 amount, bytes memory operatorNotificationData)
        public
        override(ILSP7DigitalAsset, LSP7DigitalAsset)
    {
        if (!_transferable) revert NonTransferable();
        super.authorizeOperator(operator, amount, operatorNotificationData);
    }

    function increaseAllowance(address operator, uint256 addedAmount, bytes memory operatorNotificationData)
        public
        override(ILSP7DigitalAsset, LSP7DigitalAsset)
    {
        if (!_transferable) revert NonTransferable();
        super.increaseAllowance(operator, addedAmount, operatorNotificationData);
    }
}

contract KeepFactory {
    event GroupCreated(address indexed token, address indexed owner, string name, string symbol);
    event AdminSet(address indexed token, address indexed account, bool allowed);

    error NotAllowed();

    function createGroup(
        string calldata name_,
        string calldata symbol_,
        bool transferable_,
        bool revocable_,
        bytes32 codeHash_,
        uint256 claimFrom_,
        uint256 claimUntil_,
        uint256 maxClaims_,
        bool mustFollow_,
        bool closable_
    ) external returns (address token) {
        MembershipClaim created = new MembershipClaim(
            name_,
            symbol_,
            msg.sender,
            transferable_,
            revocable_,
            codeHash_,
            claimFrom_,
            claimUntil_,
            maxClaims_,
            mustFollow_,
            closable_,
            address(this)
        );
        token = address(created);
        emit GroupCreated(token, msg.sender, name_, symbol_);
    }

    function setAdmin(address token, address account, bool allowed) external {
        MembershipClaim claim = MembershipClaim(payable(token));
        if (msg.sender != claim.owner()) revert NotAllowed();
        claim.setAdmin(account, allowed);
        emit AdminSet(token, account, allowed);
    }
}

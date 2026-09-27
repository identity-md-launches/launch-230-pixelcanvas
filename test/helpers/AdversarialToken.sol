// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Test-only token for exercising failure and callback paths absent from PIXL.
contract AdversarialToken is ERC20 {
    bool public failCollection;
    bool public failPayout;
    bool public noReturnData;
    address public blockedRecipient;
    address public hookTarget;
    bytes public hookData;
    bool public hookOnCollection;
    bool public hookOnPayout;
    bool public hookSucceeded;
    bytes public hookResult;
    uint256 public collectionCalls;

    constructor() ERC20("Test token", "TEST") {
        _mint(msg.sender, 1e27);
    }

    function setFailure(bool collection, bool payout, address blocked) external {
        failCollection = collection;
        failPayout = payout;
        blockedRecipient = blocked;
    }

    function setNoReturnData(bool enabled) external {
        noReturnData = enabled;
    }

    function setHook(address target, bytes calldata data, bool collection, bool payout) external {
        hookTarget = target;
        hookData = data;
        hookOnCollection = collection;
        hookOnPayout = payout;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (failCollection) return false;
        ++collectionCalls;
        super.transferFrom(from, to, amount);
        if (hookOnCollection) _hook();
        if (noReturnData) {
            assembly ("memory-safe") { return(0, 0) }
        }
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (failPayout || to == blockedRecipient) return false;
        super.transfer(to, amount);
        if (hookOnPayout) _hook();
        if (noReturnData) {
            assembly ("memory-safe") { return(0, 0) }
        }
        return true;
    }

    function _hook() private {
        (hookSucceeded, hookResult) = hookTarget.call(hookData);
    }
}

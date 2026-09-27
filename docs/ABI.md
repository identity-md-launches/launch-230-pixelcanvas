# Contract ABI reference

Machine-readable ABI arrays are exported directly from the pinned compiler:

- [LaunchToken.json](abi/LaunchToken.json)
- [PixelCanvas.json](abi/PixelCanvas.json)

Regenerate after any interface change:

```sh
forge inspect src/LaunchToken.sol:LaunchToken abi --json > docs/abi/LaunchToken.json
forge inspect src/PixelCanvas.sol:PixelCanvas abi --json > docs/abi/PixelCanvas.json
```

## LaunchToken

The nonpayable constructor has no arguments. Standard ERC-20 views are
`name()`, `symbol()`, `decimals()`, `totalSupply()`, `balanceOf(address)` and
`allowance(address,address)`. Mutators are `approve(address,uint256)`,
`transfer(address,uint256)` and `transferFrom(address,address,uint256)`, returning
`bool`. These use standard `Transfer` and `Approval` events and OpenZeppelin
ERC-20 custom errors. The token provides no permit interface.

## PixelCanvas

The nonpayable constructor takes a single `address token_`.

| Call | Returns / behavior |
| --- | --- |
| `token()` | Immutable ERC-20 address |
| `canvas()` | `bytes`, exactly 3,072 bytes in index-order RGB |
| `priceOf(uint256 index)` | Current charge in PIXL minor units |
| `painterOf(uint256 index)` | Last painter, or zero if never painted |
| `withdrawable(address account)` | Outstanding credit in PIXL minor units |
| `paint(uint256 index, uint24 colour)` | Paint one pixel; no return value |
| `paintBatch(uint256[] indices, uint24[] colours)` | Paint 1–64 entries in order; no return value |
| `withdraw()` | Pay the caller's whole credit; no return value |

Constant getters are `PIXEL_COUNT()` = 1024, `MAX_BATCH_SIZE()` = 64,
`INITIAL_PRICE()` = `10000000000000000000`, `MAX_PRICE()` =
`1000000000000000000000000`, and `BURN_ADDRESS()` =
`0x000000000000000000000000000000000000dEaD`.

Events:

```solidity
event Painted(uint256 indexed index, uint24 colour, address indexed painter, uint256 price);
event Withdrawn(address indexed account, uint256 amount);
```

`Painted.price` is the amount charged for that entry, not the next price. Repeated
indices emit separate events in processing order, including self-repaints and
black paints. Withdrawn is emitted only for a successful withdrawal; any revert
also rolls back its log. PIXL Transfer events show the collection, burn and
withdrawal token movements.

Application errors are `InvalidToken()`, `InvalidIndex(uint256)`,
`InvalidBatchSize()`, `LengthMismatch()`, and `NothingToWithdraw()`. Inherited
`ReentrancyGuardReentrantCall()` rejects recursive mutation.
`SafeERC20FailedOperation(address)` rejects unsuccessful ERC-20 operations;
token revert data (including insufficient allowance/balance) is propagated.

Every exposed function is nonpayable or view. No fallback, receive, initializer,
ownership, upgrade, rescue or privileged withdrawal interface is present.

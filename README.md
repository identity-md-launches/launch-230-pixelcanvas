# Pixel Wall contracts

Pixel Wall is a shared 32 × 32 canvas paid in PIXL. This contribution supplies the
contracts, offline Solidity dependencies, tests and ABI exports for the contract
stage. The target deployment is Sepolia, chain ID **11155111**.

## Build and check

Use Foundry with Solidity **0.8.26**, as pinned in `foundry.toml`. All imported
Solidity sources are ordinary files under `lib/`; no package installation,
submodules, RPC endpoint or network access is needed once the compiler is installed.
FFI and filesystem cheatcode permissions are disabled. Tests use isolated local
deployments and do not read or modify environment variables.

```sh
forge build
forge test
forge fmt --check
forge test --fuzz-runs 1000
```

The suite includes unit failures, differential batch/single painting, hostile token
callbacks, a factory constructor probe, forbidden-opcode checks and stateful
invariants. See [validation notes](docs/VALIDATION.md) and
[dependency provenance](docs/DEPENDENCIES.md).

## Contracts and deployment parameters

| Artifact | Constructor arguments | Initial state |
| --- | --- | --- |
| `src/LaunchToken.sol:LaunchToken` | none | 1,000,000,000 PIXL, 18 decimals, all minted to its deployer |
| `src/PixelCanvas.sol:PixelCanvas` | `address token_`, resolved as `$token` | Immutable PIXL reference, black canvas, no PIXL balance or liabilities |

Token metadata is **Pixel Wall / PIXL**. Supply is exactly `1000000000000000000000000000`
minor units. LaunchToken has no further minting, fees, owner, blocklist, pause or
upgrade functionality. A transfer to the burn address does **not** reduce
`totalSupply()`; it removes tokens from use by transferring them to
`0x000000000000000000000000000000000000dEaD`.

The separately assigned manifest contribution should identify `LaunchToken` as
the token and `PixelCanvas` as the sole application contract, with
`constructorArgs: ["$token"]`, under kind `evm_project`. The factory deploys the
token first and then the canvas. Both constructors are nonpayable; there are no
initializers, factory callbacks, owner arguments or deploy-time token transfers.
`PixelCanvas` rejects a token address with no code. This check cannot establish
token identity: deployment tooling and review must bind the argument to the
accepted `LaunchToken` artifact. No application funding is required at deployment.

Compiler settings are Cancun EVM, optimizer enabled with 200 runs and
`bytecode_hash = "none"`. The constructors do not restrict `block.chainid`;
deployment services and the frontend are responsible for enforcing Sepolia.

## Painting and accounting

The index is `y * 32 + x`, for coordinates from 0 through 31. All indexed entry
points reject an index of 1024 or greater. A colour is a `uint24` RGB value.
`canvas()` returns exactly 3,072 bytes: red, green, blue for pixel 0, then pixel 1,
and so on. Colours use a packed `uint24[1024]` storage array.

Each pixel starts at **10 PIXL**. A paint charges its current price, then sets the
next price to `min(floor(price * 11 / 10), 1_000_000 * 10^18)`. Black is an ordinary
colour: painting black still charges, changes the painter and raises the price.

On a pixel's first paint, the entire charge goes to the burn address. On every
repaint, `floor(price / 2)` becomes the previous painter's withdrawable credit,
and the remainder is burned immediately. For an odd price, the burn receives the
extra minor unit. Painting your own pixel is allowed and earns the same credit.

`paintBatch` accepts 1–64 entries and requires equal index/colour lengths. Entries
are processed in order; duplicates each pay the price reached by the preceding
entry. The batch makes one `safeTransferFrom` for the **full sum**, then one
transfer for the summed burns. Credits earned in the batch do not reduce the
upfront balance or allowance requirement. All state changes and transfers revert
together if any index, allowance, balance or transfer fails.

Each player first calls `PIXL.approve(canvasAddress, amount)`, then `paint` or
`paintBatch`. `withdraw()` transfers the caller's entire credit to that caller,
zeroes the credit before transferring, and rejects a zero balance. No function
can withdraw for or redirect another player's credit. All three mutating canvas
entry points share a reentrancy guard. There are no privileged roles, timeouts,
or required keepers.

For completed application operations, starting unfunded and without unsolicited
transfers:

```text
PIXL.balanceOf(PixelCanvas) = sum(withdrawable(player))
total payments = tokens sent to the burn address + outstanding credits + withdrawals
```

Anyone can transfer an ERC-20 directly to any address, so literal balance equality
cannot hold under arbitrary unsolicited PIXL transfers. Such a transfer produces
an uncredited, unrecoverable surplus; existing credits remain payable. There is no
sweep or rescue authority. With donations, the relation is balance = credits +
surplus. The suite demonstrates this limitation separately from the application
accounting invariant. Fee-on-transfer, rebasing and arbitrary substitute tokens
are unsupported; production deployment must use the delivered PIXL token.

The canvas has no payable entry point, receive or fallback function. Ordinary ETH
transfers revert. EVM mechanisms can nevertheless force ETH into any address;
forced ETH has no application meaning and cannot be recovered.

## ABI and frontend handoff

See the [ABI reference](docs/ABI.md) and JSON arrays in
[docs/abi](docs/abi). Amounts are always integer minor units; frontend calculations
must use integer arithmetic, not floating point.

The later one-page frontend should read the token address from `token()`, load
`canvas()`, and apply `Painted` events in log order. Read `priceOf`, PIXL balance,
allowance and `withdrawable` before presenting a transaction. Repeated indices in
a queued batch require sequential local price updates when computing its total.
Prices may change before inclusion; there is no deadline or maximum-cost
argument. An exact allowance bounds the gross spend; a stale insufficient
allowance makes the transaction revert. A larger existing allowance permits
charging the newer on-chain price. Refresh quotes and require an explicit
Approve step before each paying action, and expose Withdraw separately.

Players acquire PIXL by swapping Sepolia ETH in the factory-seeded launch pool;
the canvas has no faucet and the planned page has no in-page swap. The frontend
uses views and events without a backend/indexer, with site label
`lab-pixel-canvas` and a static export containing `dist/index.html`.

## Operational responsibilities and review

The separate manifest assignment supplies `launch.json`. An independent reviewer
must inspect accepted source and the exact manifest, including the token address
binding, rounding, cap, duplicate pricing and withdrawals. Local adversarial tests
in this contribution are evidence for that review, not an independent audit.

Services are responsible for policy and signed-artifact linkage, source
publication, attestation, admission, factory deployment and distribution to the
launch pool/rewards. They must retain the constructor arguments, artifact
identities, addresses and deployment block for verification and event reads.
The frontend assignment begins against that live deployment. This source
contribution performs no deployment, wallet operation, publication or independent
approval, and those later outcomes are not prerequisites for these local checks.

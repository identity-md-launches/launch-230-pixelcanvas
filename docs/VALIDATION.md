# Local validation and review handoff

Compiler: Solidity 0.8.26. Local runner: Foundry 1.7.1. EVM: Cancun.

Recorded local results:

| Check | Result |
| --- | --- |
| `forge fmt --check` | Passed |
| `forge build` | Passed with the pinned 0.8.26 compiler |
| `forge test` | 39 passed, 0 failed, 0 skipped |
| `forge test --fuzz-runs 1000` | 39 passed, 0 failed, 0 skipped; each fuzz test ran 1,000 cases |
| Stateful invariants in both test runs | Each passed 128 runs / 16,384 calls with 0 unexpected reverts |
| Exported ABI comparison | Both JSON ABI arrays exactly match compiler artifacts |

The local suite has 39 tests across six suites, including two stateful
invariants. Each invariant runs 128 sequences at depth 128, with unexpected
handler reverts treated as failures. The four-actor model independently tracks
prices, previous painters, colours, credits, burns and withdrawals. At the end
of each sequence all actors withdraw and the canvas must be empty.

| Evidence | Covered behavior |
| --- | --- |
| `test/LaunchToken.t.sol` | Metadata, fixed factory supply, exact transfer conservation, allowance handling, invalid transfers, absent mint/admin selectors |
| `test/PixelCanvas.t.sol` | Complete blank canvas, RGB packing across storage/row boundaries, individual prices, first/repaint/self splits, real odd prices, cap crossing and persistence, batch size limits, ordered duplicate events, one collection, index failures, payment rollback, withdrawals and ETH rejection |
| `test/PixelCanvasDifferential.t.sol` | Fuzzed duplicate batches equal sequential individual paints in charge, burn, credit, prices, painters and colours; 64 duplicate paints crossing the cap |
| `test/PixelCanvasAdversarial.t.sol` | False-return collection and burn rollback, safe empty-return transfers, failed withdrawal restores credit, another recipient can withdraw, callback reentry blocked at collection/burn/withdrawal, credit is zero before payout |
| `test/PixelCanvasInvariant.t.sol` | Contract balance equals model credits; every collected unit is burned, owed or withdrawn; fixed supply conservation; independent sequential pricing and painter model; eventual withdrawal of every liability |
| `test/Deployment.t.sol` | Sepolia chain context, CREATE2 factory constructor semantics, factory retains the full supply, unfunded app construction, runtime size and no DELEGATECALL/CALLCODE/SELFDESTRUCT |

Commands to reproduce:

```sh
forge fmt --check
forge build
forge test
forge test --fuzz-runs 1000
```

Successful local checks are contributor evidence only. The supplied protected
tests require verifier-provided deployment artifacts/environment; this suite
does not claim to run those protected tests. The local factory probe exercises
the same relevant constructor/supply/runtime conditions without reading
environment variables. No live pool, service admission, deployment, signed
manifest or independent review is simulated as successful.

The local review specifically challenged rounding, the cap, ordered duplicate
costs and callback-driven withdrawals. Runtime sizes under the pinned optimized
settings are 1,722 bytes for LaunchToken and 2,843 bytes for PixelCanvas, both
below the 24,576-byte limit.

The independent reviewer should verify the exact manifest uses the delivered
PIXL token, constructor arguments contain no privileges, and the accepted
source matches these ABIs. The application assumes that exact-transfer token;
the constructor does not authenticate arbitrary token semantics. Unsolicited
PIXL transfers create irrecoverable surplus, and forced ETH cannot be rejected
at the EVM level. Those limits are demonstrated or explained in the README.
The fixed API has no maximum-cost/deadline argument, so quoted prices can become
stale; an exact allowance limits spending. These are operational assumptions,
not assertions that later review or deployment has already happened.

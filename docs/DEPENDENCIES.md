# Vendored dependency provenance

All dependency code is checked in as ordinary source files. There are no
submodules, package-manager install hooks or compiler binaries in this project.
Dependencies were copied unmodified from these pinned source archives:

| Library | Release | Included files |
| --- | --- | --- |
| OpenZeppelin Contracts | v5.1.0 | Transitive Solidity imports of ERC20, SafeERC20 and ReentrancyGuard, plus MIT license |
| forge-std | v1.9.4 | `src/` plus MIT and Apache-2.0 licenses; tests only |

Archive locations and SHA-256 digests:

```text
https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0
8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686

https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.4
9bf191808ba79584a69ee4f288bfb9f217d1187c43d46f59780d86cab9196a15
```

`remappings.txt` resolves every import locally. The `lib/` licenses apply to
their respective dependencies; first-party Solidity files use SPDX MIT.

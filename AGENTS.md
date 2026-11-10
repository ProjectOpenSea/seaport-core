# seaport-core

The Seaport 1.6 contracts, without tests or helpers. Canonical Seaport 1.6 at `0x0000000000000068F116a894984e2DB1123eB395` was built from `src/` with the settings in `foundry.toml`. Tests, docs, and deployment steps live in [seaport](https://github.com/ProjectOpenSea/seaport), which pulls this repo in as `lib/seaport-core`.

## Rule

The source must keep building the deployed bytecode. Don't change any file under `src/` (not even whitespace), the `lib/seaport-types` pin, or any compiler setting in `foundry.toml`. `scripts/check-deployed-bytecode.sh` fails if the build stops matching the canonical init code, and `scripts/frozen-src.sha256` fails lint if a file in `src/` changes.

`src/conduit/ConduitController.sol` differs from the deployed ConduitController at `0x00000000F9490004C11Cef243f5400493c00Ad63`, which was built from seaport 1.1. Leave it as is.

## Commands

Foundry v1.9.0, submodules checked out recursively.

```bash
forge build
scripts/check-deployed-bytecode.sh   # needs jq
scripts/install-tools.sh             # pinned Biome, taplo, lefthook, shellcheck, shfmt, actionlint
scripts/lint.sh check
```

## npm

The package is published to npm as `seaport-core` when a GitHub release is created (`.github/workflows/publish.yml`). It ships `src/` and depends on the `seaport-types` npm package, whose version matches the `lib/seaport-types` pin. Bump `version` in `package.json` before a release, and keep `files` as it is so the published layout stays the same.

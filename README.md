# seaport-core

[![Version][version-badge]][version-link]
[![npm][npm-badge]][npm-link]

The core Seaport 1.6 contracts, with no reference contracts, helpers, or tests. Build on Seaport from here without the long compile times of the [main Seaport repo][seaport].

Canonical Seaport 1.6 is deployed at `0x0000000000000068F116a894984e2DB1123eB395` on every supported chain, built from `src/` with the settings in `foundry.toml`. CI checks that the build still matches the deployed init code.

## Install

With Foundry:

```bash
forge install ProjectOpenSea/seaport-core
```

With npm:

```bash
npm install seaport-core
```

## Development

```bash
git submodule update --init --recursive
forge build
scripts/check-deployed-bytecode.sh
scripts/install-tools.sh && scripts/lint.sh check
```

The source in `src/` is frozen. See [AGENTS.md](AGENTS.md).

## More

- [Seaport docs][seaport-docs]
- [Deployments][seaport-deployments], and [deploying to a new chain][seaport-deploying]
- [seaport-types][seaport-types], the interfaces, structs, and constants Seaport uses

[seaport]: https://github.com/ProjectOpenSea/seaport
[seaport-docs]: https://github.com/ProjectOpenSea/seaport/blob/main/docs/SeaportDocumentation.md
[seaport-deployments]: https://github.com/ProjectOpenSea/seaport/blob/main/docs/Deployments.md
[seaport-deploying]: https://github.com/ProjectOpenSea/seaport/blob/main/docs/Deploying.md
[seaport-types]: https://github.com/ProjectOpenSea/seaport-types
[version-badge]: https://img.shields.io/github/package-json/v/ProjectOpenSea/seaport-core
[version-link]: https://github.com/ProjectOpenSea/seaport-core/releases
[npm-badge]: https://img.shields.io/npm/v/seaport-core?color=red
[npm-link]: https://www.npmjs.com/package/seaport-core

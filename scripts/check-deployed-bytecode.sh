#!/usr/bin/env bash
# Usage: scripts/check-deployed-bytecode.sh
#
# Builds Seaport with foundry.toml's settings and checks that its init code
# (creation code plus the ConduitController constructor argument) hashes to
# the init code of canonical Seaport 1.6, and that the hash and salt derive
# the canonical address through the ImmutableCreate2Factory. A toolchain,
# dependency, or setting change that alters the contract fails here.
#
# Needs forge, cast, and jq.
set -euo pipefail

cd "$(dirname "$0")/.."

# Canonical Seaport 1.6, deployed at the same address on every chain.
seaport=0x0000000000000068F116a894984e2DB1123eB395
# Constructor argument of the canonical deployment.
conduit_controller=0x00000000F9490004C11Cef243f5400493c00Ad63
# ImmutableCreate2Factory and the salt passed to it in Ethereum mainnet
# tx 0x926e958d5919f0089f47a353b0a8a211bd858abb20348261d41672d77fa7c6a0.
factory=0x0000000000FFe8B47B3e2130213B802212439497
salt=0x0000000000000000000000000000000000000000d738b7f0bb99901b1c83f249
# keccak256 of the init code deployed in that transaction.
init_code_hash=0xde057106c8377de87f4547af6ef65fa2c96fddbc136be5748060ed7c32902d94

lower() { tr '[:upper:]' '[:lower:]'; }

status=0

derived="$(cast compute-address "$factory" --salt "$salt" --init-code-hash "$init_code_hash" | grep -oE '0x[0-9a-fA-F]{40}' || true)"
if [ "$(lower <<<"$derived")" = "$(lower <<<"$seaport")" ]; then
    echo "ok: init code hash and salt derive $seaport"
else
    echo "error: init code hash and salt derive $derived, expected $seaport" >&2
    status=1
fi

forge build >/dev/null
creation_code="$(jq -er '.bytecode.object' out/Seaport.sol/Seaport.json)"
constructor_args="$(cast abi-encode 'constructor(address)' "$conduit_controller")"
actual="$(cast keccak "${creation_code}${constructor_args#0x}")"
if [ "$actual" = "$init_code_hash" ]; then
    echo "ok: Seaport build matches the deployed 1.6 init code ($init_code_hash)"
else
    echo "error: Seaport build init code hash is $actual, expected $init_code_hash" >&2
    status=1
fi

exit "$status"

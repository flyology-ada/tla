# Toolchain provisioning contract

`flyology-tla toolchain install [ABSOLUTE_ROOT]` installs an isolated toolchain. With no argument, the root is
`$FLYOLOGY_TLA_TOOLCHAIN`, then `$XDG_CACHE_HOME/flyology-tla/toolchain`, or finally
`$HOME/.cache/flyology-tla/toolchain`.

The root must be a dedicated absolute leaf directory. `/`, direct children of `/`, `HOME`, `XDG_CACHE_HOME`, paths
with `.`/`..` components, line breaks, single quotes, repeated separators, trailing separators, and symbolic-link roots
are rejected before replacement. An existing root is replaced only after the complete existing installation verifies.

## Pinned inputs

The machine-readable authority is `toolchain/toolchain.lock.json`:

- TLA+ Tools 1.8.0 revision `1239539`; exact official asset ID and `tla2tools.jar` SHA-256. The installer fetches
  the asset-id endpoint rather than the mutable tag download path.
- TLAPS 1.6.0-pre revision `4600b24`; exact official archive SHA-256 per platform. The macOS arm64 extracted `tlapm`
  binary is additionally exact-hash pinned.
- Eclipse Temurin feature 21, latest GA at installation time. This moving choice is converted to immutable local
  provenance in `receipt.json`.

The official TLAPS binary release currently constrains support to macOS arm64 and Linux x86_64. This is a binary
availability boundary, not a claim that the Ada library cannot build elsewhere.

## Commands and environment

```sh
flyology-tla toolchain install /absolute/dedicated/toolchain
flyology-tla toolchain verify /absolute/dedicated/toolchain
eval "$(flyology-tla toolchain env /absolute/dedicated/toolchain)"
```

The final command emits single-quoted assignments for:

- `FLYOLOGY_TLA_TOOLCHAIN`
- `FLYOLOGY_TLA_JAVA`
- `FLYOLOGY_TLA_TLC_JAR`
- `FLYOLOGY_TLAPM`

It emits nothing unless verification succeeds. The root restrictions make those assignments safe to evaluate.

The installer requires POSIX `sh`, `curl`, `tar`, `find`, `awk`, `sed`, and either `sha256sum` or `shasum`. Network
installation downloads the official GitHub release assets and Adoptium API result. No global Java or package-manager
mutation occurs.

`tests/scripts/test-toolchain.sh` is a hermetic path/safety test. Its tiny fake executables are test fixtures and are
not toolchain validation. The actual TLC and exact TLAPM binaries are exercised by `scripts/check-formal.sh`.

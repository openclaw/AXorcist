# Releasing AXorcist and axorc

The release workflow publishes the SwiftPM version and three Developer ID-signed,
notarized CLI archives: universal, arm64 and x86_64. Each archive contains only
`axorc`, retains mode 0755, and keeps the established `axorc` signing identifier
and OpenClaw Foundation Team ID. Individual `.sha256` files remain available;
`SHA256SUMS`, `ASSET-INVENTORY.json`, and the exact changelog notes cover the complete release.

## Prepare and rehearse

Update `VERSION` and `axorcVersion` in `Sources/axorc/Models/AXORCModels.swift`.
Finalize exactly one dated `## [X.Y.Z] - YYYY-MM-DD` changelog section, leaving
`Unreleased` above it. Merge the preparation PR and wait for green push CI on that
exact protected-main commit. Rehearse with:

```sh
gh workflow run release.yml --repo openclaw/AXorcist --ref main -f version=X.Y.Z -F dry_run=true
```

Dispatch is rehearsal-only and defaults to `dry_run: true`; false is rejected.
The rehearsal runs the shared `release-source@v1` protected-source, version,
changelog and exact-push-CI gates, builds the universal CLI, signs and notarizes
all archives, then independently checks them on Apple Silicon and Intel.
It creates no tag, GitHub Release, or Homebrew dispatch. An existing release for
the requested version does not redirect the rehearsal away from current main.

## Publish

Push an SSH-signed annotated `vX.Y.Z` tag for the verified protected-main commit,
using the key authorized by `.github/release-allowed-signers`. Signing key custody
stays outside Actions. The same build and independent verification run before a
publisher compares both attestations, stages and downloads every release asset,
rechecks the immutable tag, and publishes. Existing versions are rejected; never
move a tag or overwrite a release. A failed draft stays available for inspection;
resolve it deliberately before retrying, never delete published assets to retry.

The final job dispatches `openclaw/homebrew-tap` using its archive-template
contract for the native ZIP files, waits for the matching run, and checks the
result against the exact verified archive names and hashes. It verifies the resulting
formula preserves those URLs, hashes, and `skip_clean "bin/axorc"`. Verify the
workflow, public downloads, and a clean `brew install openclaw/tap/axorc` after
release. Keep networking enabled for standalone executable notarization checks.

## Why a repository-owned binary workflow

The current `release-swift-cli@v1` requires an imsg-specific helper dylib and Linux
archive, has no no-publish rehearsal input, and cannot retain this project's
three established versioned macOS archives. AXorcist is macOS-only and has no
helper dylib. Its workflow therefore reuses `release-source@v1` for the shared
source gate and owns only the required binary signing, verification and tap
handoff. Actions are SHA-pinned and write/signing credentials are isolated from
build and verifier jobs. No npm or Sparkle channel exists.

Required repository secrets: `MACOS_SIGNING_P12`, `MACOS_SIGNING_P12_PASSWORD`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_P8`, `HOMEBREW_TAP_TOKEN`.

## Local checks

`make check` retains source-only regressions. `make verify-release-packaging VERSION=X.Y.Z` builds ad-hoc packaging fixtures; these cannot be published.
The former local Developer ID and manual publishing path has been removed.
Read-only formula rendering and checksum verification remain available.

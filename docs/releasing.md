# Releasing `axorc`

The Homebrew formula consumes a Developer ID-signed binary for the host architecture, or the universal binary for older releases. Do not publish the ad-hoc artifact produced by `--adhoc`; a stable signature keeps the macOS Accessibility identity consistent across upgrades.

Release packaging also produces smaller `macos-arm64` and `macos-x86_64` archives for Apple Silicon and Intel Macs. Each contains only `axorc`, extracted from the signed universal binary without changing its signature. The universal archive remains available for both architectures.

`scripts/build-universal-binary.sh` restores executable mode `0755` after stripping and signing, regardless of the caller's umask. The release archive preserves that mode. Run `make test-universal-binary-mode` for the source-only permission regression; it mocks build/signing tools and does not replace native signature or archive verification.

## Prepare

1. Update `axorcVersion` in `Sources/axorc/Models/AXORCModels.swift` and move the changelog entries into the matching release section.
2. Run `swift test`, SwiftFormat, SwiftLint, the live CLI smoke checks, and autoreview.
3. Build with the existing Developer ID Application identity:

   ```bash
   AXORC_CODESIGN_IDENTITY='Developer ID Application: ...' scripts/build-release-artifact.sh 0.1.11
   ```

4. Submit each `dist/axorc-0.1.11-macos-*.zip` archive to `notarytool` using the approved release credentials. Wait for acceptance. Zip archives cannot be stapled; verify each downloaded executable's notarization ticket online after publication.

## Publish and update Homebrew

1. Upload all three zips and their `.sha256` files to the matching GitHub Release.
2. Download each public artifact into a clean temporary directory. Verify its checksum, advertised architectures, stable signature, and executable mode. Run `--version` and `--help` on a matching host. Verify the standalone executable's notarization ticket with:

   ```bash
   codesign -vvvv -R="notarized" --check-notarization axorc
   ```

   `spctl --assess --type execute` is an app assessment and can reject valid standalone executables as not being apps. Follow Apple's [Testing a Notarised Product](https://developer.apple.com/forums/thread/130560) guidance for other code, and also test the actual install and launch on a fresh Mac or VM. Keep networking enabled because the zip cannot carry a stapled ticket.
3. Render the formula from the directory containing the public archives and checksum files verified above:

   ```bash
   scripts/render-homebrew-formula.sh 0.1.11 --artifacts <verified-directory> > axorc.rb
   ```

   The renderer checks each checksum against its archive and selects thin downloads only when both architecture pairs are present. An incomplete set fails. A directory with only the universal pair, or the existing `scripts/render-homebrew-formula.sh 0.1.10 <sha256>` invocation, renders a universal formula for older releases. Rendering does not replace the signature and notarization checks above or publish anything.

4. Add `axorc.rb` to `openclaw/homebrew-tap`, then run `brew audit --strict openclaw/tap/axorc`, `brew install --build-from-source openclaw/tap/axorc`, `brew test openclaw/tap/axorc`, `axorc --version`, `axorc --help`, and `axorc permissions` on a clean host for each architecture.
5. Confirm Homebrew preserved the published executable byte-for-byte and retained its Developer ID requirement:

   ```bash
   cmp axorc "$(brew --prefix axorc)/bin/axorc"
   codesign --verify --strict "$(brew --prefix axorc)/bin/axorc"
   codesign -d -r- "$(brew --prefix axorc)/bin/axorc"
   ```

   The designated requirement must contain `anchor apple generic`; an ad-hoc requirement is a release blocker.
6. After the tap change lands, update the README with `brew install openclaw/tap/axorc` and verify a fresh public installation.

## Close out

- Confirm the GitHub Release contains the signed universal, arm64, and x86_64 archives and their checksums.
- Confirm the Homebrew formula uses the public archive URL and exact checksum.
- Open the next patch `Unreleased` section and commit it.

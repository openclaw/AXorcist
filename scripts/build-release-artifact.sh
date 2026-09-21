#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-release-artifact.sh <version> [--adhoc]

Builds universal, arm64, and x86_64 dist/axorc-<version>-macos-<arch>.zip
archives and their SHA-256 files.

Release builds require AXORC_CODESIGN_IDENTITY to name a Developer ID
Application identity already available in the current keychain. Use --adhoc
only for local or CI verification; ad-hoc artifacts must not be published.
EOF
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

version="$1"
shift
adhoc=false

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must use x.y.z form." >&2
  exit 2
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --adhoc)
      adhoc=true
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

source_version="$(sed -n 's/.*axorcVersion = "\([^"]*\)".*/\1/p' Sources/axorc/Models/AXORCModels.swift)"
if [[ "$source_version" != "$version" ]]; then
  echo "Version mismatch: source has $source_version, requested $version" >&2
  exit 1
fi

if [[ "$adhoc" == false && -z "${AXORC_CODESIGN_IDENTITY:-}" ]]; then
  echo "AXORC_CODESIGN_IDENTITY is required for publishable artifacts." >&2
  exit 1
fi

dist_dir="$repo_root/dist"
stage_dir="$dist_dir/stage"
binary_path="$stage_dir/axorc"

rm -rf "$stage_dir"
for architecture in universal arm64 x86_64; do
  archive_path="$dist_dir/axorc-$version-macos-$architecture.zip"
  rm -f "$archive_path" "$archive_path.sha256"
done
mkdir -p "$stage_dir"

if [[ "$adhoc" == true ]]; then
  "$repo_root/scripts/build-universal-binary.sh" "$binary_path" --adhoc
else
  "$repo_root/scripts/build-universal-binary.sh" "$binary_path"
fi

codesign --verify --strict --verbose=2 "$binary_path"
lipo "$binary_path" -verify_arch arm64 x86_64
"$binary_path" --version | grep -Fx "axorc $version"

for architecture in universal arm64 x86_64; do
  archive_path="$dist_dir/axorc-$version-macos-$architecture.zip"
  checksum_path="$archive_path.sha256"
  package_dir="$stage_dir"
  if [[ "$architecture" != universal ]]; then
    package_dir="$stage_dir/$architecture"
    mkdir -p "$package_dir"
    # Each Mach-O slice carries its signature. Extract it without changing or
    # re-signing the code so every archive keeps the same Accessibility identity.
    lipo "$binary_path" -thin "$architecture" -output "$package_dir/axorc"
    chmod 0755 "$package_dir/axorc"
    test "$(lipo -archs "$package_dir/axorc")" = "$architecture"
    codesign --verify --strict --verbose=2 "$package_dir/axorc"
  fi
  (
    cd "$package_dir"
    ditto --norsrc -c -k axorc "$archive_path"
  )
  (
    cd "$dist_dir"
    shasum -a 256 "$(basename "$archive_path")"
  ) | tee "$checksum_path"
  echo "Created $archive_path"
done

rm -rf "$stage_dir"

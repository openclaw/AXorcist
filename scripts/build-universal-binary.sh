#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-universal-binary.sh <output-path>

Builds an ad-hoc universal axorc binary for local verification only.
Developer ID release signing belongs to the GitHub Actions release pipeline.
EOF
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

output_path="$1"
shift
if [[ $# -ne 0 ]]; then
  usage >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

build_arguments=(-c release --arch arm64 --arch x86_64 --product axorc)
swift build "${build_arguments[@]}"
bin_dir="$(swift build "${build_arguments[@]}" --show-bin-path)"
built_binary="$bin_dir/axorc"
if [[ ! -x "$built_binary" ]]; then
  echo "Built universal axorc binary is missing: $built_binary" >&2
  exit 1
fi

for architecture in arm64 x86_64; do
  if ! lipo "$built_binary" -verify_arch "$architecture"; then
    echo "Built axorc binary is missing the $architecture architecture: $built_binary" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$output_path")"
install -m 0755 "$built_binary" "$output_path"
strip -x "$output_path"

codesign --force --sign - "$output_path"

# Rewriting tools can narrow permissions under a restrictive caller umask.
chmod 0755 "$output_path"

codesign --verify --strict --verbose=2 "$output_path"
for architecture in arm64 x86_64; do
  lipo "$output_path" -verify_arch "$architecture"
done
echo "Created universal binary $output_path"

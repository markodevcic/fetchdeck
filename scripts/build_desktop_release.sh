#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUESTED_PLATFORM="${1:-current}"

current_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

host_platform="$(current_platform)"
platform="$REQUESTED_PLATFORM"
if [[ "$platform" == "current" ]]; then
  platform="$host_platform"
fi

case "$platform" in
  macos|windows|linux) ;;
  *)
    echo "Unsupported platform: $platform" >&2
    echo "Usage: scripts/build_desktop_release.sh [current|macos|windows|linux]" >&2
    exit 1
    ;;
esac

if [[ "$platform" != "$host_platform" ]]; then
  echo "Cannot build $platform from $host_platform with Flutter desktop." >&2
  echo "Run this script on the target OS, or use CI runners for each platform." >&2
  exit 1
fi

if ! command -v fvm >/dev/null 2>&1; then
  echo "fvm is required. Install FVM and run fvm install before building." >&2
  exit 1
fi

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/prepare_platform_tools.sh" "$platform"
fvm flutter pub get
fvm flutter build "$platform" --release

case "$platform" in
  macos)
    app_path="$(find "$ROOT_DIR/build/macos/Build/Products/Release" -maxdepth 1 -name "*.app" -print -quit)"
    echo "Release app: ${app_path#$ROOT_DIR/}"
    ;;
  windows)
    echo "Release folder: build/windows/x64/runner/Release"
    ;;
  linux)
    echo "Release bundle: build/linux/x64/release/bundle"
    ;;
esac

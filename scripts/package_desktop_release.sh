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

app_version() {
  awk '/^version:/ {print $2; exit}' "$ROOT_DIR/pubspec.yaml" | tr '+' '-'
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
    echo "Usage: scripts/package_desktop_release.sh [current|macos|windows|linux]" >&2
    exit 1
    ;;
esac

if [[ "$platform" != "$host_platform" ]]; then
  echo "Cannot package $platform from $host_platform with Flutter desktop." >&2
  echo "Run this script on the target OS, or use CI runners for each platform." >&2
  exit 1
fi

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/build_desktop_release.sh" "$platform"

version="$(app_version)"
dist_dir="$ROOT_DIR/dist"
mkdir -p "$dist_dir"

case "$platform" in
  macos)
    app_path="$(find "$ROOT_DIR/build/macos/Build/Products/Release" -maxdepth 1 -name "*.app" -print -quit)"
    if [[ -z "$app_path" ]]; then
      echo "Could not find built macOS .app" >&2
      exit 1
    fi
    artifact="$dist_dir/fetchdeck-$version-macos.zip"
    rm -f "$artifact"
    ditto -c -k --norsrc --keepParent "$app_path" "$artifact"
    ;;
  windows)
    release_dir="$ROOT_DIR/build/windows/x64/runner/Release"
    artifact="$dist_dir/fetchdeck-$version-windows.zip"
    rm -f "$artifact"
    powershell.exe -NoProfile -Command "Compress-Archive -Path '$release_dir\\*' -DestinationPath '$artifact' -Force"
    ;;
  linux)
    bundle_dir="$ROOT_DIR/build/linux/x64/release/bundle"
    artifact="$dist_dir/fetchdeck-$version-linux.tar.gz"
    rm -f "$artifact"
    tar -czf "$artifact" -C "$bundle_dir" .
    ;;
esac

echo "Packaged release: $artifact"

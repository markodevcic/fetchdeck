#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/assets/tools"
REQUESTED_PLATFORM="${1:-current}"

current_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

platform="$REQUESTED_PLATFORM"
if [[ "$platform" == "current" ]]; then
  platform="$(current_platform)"
fi

case "$platform" in
  macos|windows|linux) ;;
  *)
    echo "Unsupported platform: $platform" >&2
    echo "Usage: scripts/prepare_platform_tools.sh [current|macos|windows|linux]" >&2
    exit 1
    ;;
esac

source_dir="$TOOLS_DIR/$platform"
current_dir="$TOOLS_DIR/current"

if [[ ! -d "$source_dir" ]]; then
  echo "Missing tool source directory: $source_dir" >&2
  exit 1
fi

rm -rf "$current_dir"
mkdir -p "$current_dir"

case "$platform" in
  windows)
    for tool in yt-dlp.exe ffmpeg.exe ffprobe.exe; do
      cp "$source_dir/$tool" "$current_dir/$tool"
    done
    ;;
  macos|linux)
    for tool in yt-dlp ffmpeg ffprobe; do
      cp "$source_dir/$tool" "$current_dir/$tool"
    done
    chmod +x "$current_dir/yt-dlp" "$current_dir/ffmpeg" "$current_dir/ffprobe"
    ;;
esac

if [[ -f "$source_dir/manifest.json" ]]; then
  cp "$source_dir/manifest.json" "$current_dir/manifest.json"
else
  cat > "$current_dir/manifest.json" <<'JSON'
{
  "yt-dlp": "bundled",
  "ffmpeg": "bundled",
  "ffprobe": "bundled"
}
JSON
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$current_dir" 2>/dev/null || true
fi

echo "Prepared $platform tools in $current_dir"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/assets/tools"
TMP_DIR="${TMPDIR:-/tmp}/fetchdeck-tools"
REQUESTED_PLATFORM="${1:-current}"

mkdir -p "$TOOLS_DIR/macos" "$TOOLS_DIR/windows" "$TOOLS_DIR/linux" "$TMP_DIR"

download() {
  local url="$1"
  local output="$2"
  echo "Downloading $url"
  curl -L --fail --retry 3 --output "$output" "$url"
}

current_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

should_download() {
  local platform="$1"
  local requested="$REQUESTED_PLATFORM"
  if [[ "$requested" == "current" ]]; then
    requested="$(current_platform)"
  fi
  [[ "$requested" == "all" || "$requested" == "$platform" ]]
}

download_yt_dlp_macos() {
  download \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" \
    "$TOOLS_DIR/macos/yt-dlp"
  chmod +x "$TOOLS_DIR/macos/yt-dlp"
}

download_yt_dlp_windows() {
  download \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" \
    "$TOOLS_DIR/windows/yt-dlp.exe"
}

download_yt_dlp_linux() {
  download \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux" \
    "$TOOLS_DIR/linux/yt-dlp"
  chmod +x "$TOOLS_DIR/linux/yt-dlp"
}

download_macos_ffmpeg() {
  local ffmpeg_zip="$TMP_DIR/ffmpeg-macos.zip"
  local ffprobe_zip="$TMP_DIR/ffprobe-macos.zip"

  download "https://evermeet.cx/ffmpeg/getrelease/zip" "$ffmpeg_zip"
  download "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip" "$ffprobe_zip"

  unzip -p "$ffmpeg_zip" ffmpeg > "$TOOLS_DIR/macos/ffmpeg"
  unzip -p "$ffprobe_zip" ffprobe > "$TOOLS_DIR/macos/ffprobe"
  chmod +x "$TOOLS_DIR/macos/ffmpeg" "$TOOLS_DIR/macos/ffprobe"
}

download_windows_ffmpeg() {
  local archive="$TMP_DIR/ffmpeg-windows.zip"
  local extract_dir="$TMP_DIR/ffmpeg-windows"

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  download "https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip" "$archive"
  unzip -q "$archive" -d "$extract_dir"

  cp "$extract_dir"/ffmpeg-*/bin/ffmpeg.exe "$TOOLS_DIR/windows/ffmpeg.exe"
  cp "$extract_dir"/ffmpeg-*/bin/ffprobe.exe "$TOOLS_DIR/windows/ffprobe.exe"
}

download_linux_ffmpeg() {
  local archive="$TMP_DIR/ffmpeg-linux.tar.xz"
  local extract_dir="$TMP_DIR/ffmpeg-linux"

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  download "https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-linux64-gpl.tar.xz" "$archive"
  tar -xJf "$archive" -C "$extract_dir" --strip-components=1

  cp "$extract_dir/bin/ffmpeg" "$TOOLS_DIR/linux/ffmpeg"
  cp "$extract_dir/bin/ffprobe" "$TOOLS_DIR/linux/ffprobe"
  chmod +x "$TOOLS_DIR/linux/ffmpeg" "$TOOLS_DIR/linux/ffprobe"
}

if should_download "macos"; then
  download_yt_dlp_macos
  download_macos_ffmpeg
fi

if should_download "windows"; then
  download_yt_dlp_windows
  download_windows_ffmpeg
fi

if should_download "linux"; then
  download_yt_dlp_linux
  download_linux_ffmpeg
fi

find "$TOOLS_DIR" -type f \( -name "yt-dlp" -o -name "ffmpeg" -o -name "ffprobe" \) -exec chmod +x {} \;

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$TOOLS_DIR" 2>/dev/null || true
fi

if [[ "$REQUESTED_PLATFORM" != "all" ]]; then
  "$ROOT_DIR/scripts/prepare_platform_tools.sh" "$REQUESTED_PLATFORM"
fi

echo "Bundled tools are ready in $TOOLS_DIR"
echo "Usage: scripts/download_tools.sh [current|macos|windows|linux|all]"

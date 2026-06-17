#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/build/macos-direct-dmg"
APP_NAME="Fetchdeck"
BUNDLE_NAME="$APP_NAME.app"

usage() {
  cat <<'USAGE'
Usage: scripts/package_macos_direct.sh [--no-build] [--sign] [--notarize]

Creates a drag-to-Applications macOS DMG in dist/.

Options:
  --no-build   Package the existing release .app without rebuilding.
  --sign       Sign the .app and .dmg with Developer ID.
  --notarize   Submit the signed DMG to Apple notary service and staple it.

Environment for --sign:
  MACOS_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"

Environment for --notarize, choose one:
  NOTARY_PROFILE="profile-created-with-xcrun-notarytool-store-credentials"

  or:
  APPLE_ID="you@example.com"
  APPLE_TEAM_ID="TEAMID"
  APPLE_APP_PASSWORD="app-specific-password"

Optional:
  MACOS_ENTITLEMENTS="macos/Runner/Release.entitlements"
USAGE
}

current_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    *) echo "unsupported" ;;
  esac
}

app_version() {
  awk '/^version:/ {print $2; exit}' "$ROOT_DIR/pubspec.yaml" | tr '+' '-'
}

find_release_app() {
  find "$ROOT_DIR/build/macos/Build/Products/Release" \
    -maxdepth 1 \
    -name "*.app" \
    -print \
    -quit
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required but was not found." >&2
    exit 1
  fi
}

sign_app() {
  local app_path="$1"
  local identity="${MACOS_CODESIGN_IDENTITY:-}"
  local entitlements="${MACOS_ENTITLEMENTS:-macos/Runner/Release.entitlements}"

  if [[ -z "$identity" ]]; then
    echo "MACOS_CODESIGN_IDENTITY is required for --sign." >&2
    exit 1
  fi

  echo "Removing extended attributes before signing..."
  xattr -cr "$app_path" || true

  echo "Signing $app_path with $identity..."
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "$ROOT_DIR/$entitlements" \
    --sign "$identity" \
    "$app_path"

  codesign --verify --deep --strict --verbose=2 "$app_path"
  spctl --assess --type execute --verbose=4 "$app_path" || true
}

create_dmg() {
  local app_path="$1"
  local dmg_path="$2"
  local volume_name="$3"

  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR"
  cp -R "$app_path" "$STAGING_DIR/$BUNDLE_NAME"
  ln -s /Applications "$STAGING_DIR/Applications"

  rm -f "$dmg_path"
  hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$dmg_path"
}

sign_dmg() {
  local dmg_path="$1"
  local identity="${MACOS_CODESIGN_IDENTITY:-}"

  echo "Signing $dmg_path..."
  codesign --force --timestamp --sign "$identity" "$dmg_path"
  codesign --verify --verbose=2 "$dmg_path"
}

notary_args() {
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "--keychain-profile" "$NOTARY_PROFILE"
    return
  fi

  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    echo "--apple-id" "$APPLE_ID" "--team-id" "$APPLE_TEAM_ID" "--password" "$APPLE_APP_PASSWORD"
    return
  fi

  echo "Notarization requires NOTARY_PROFILE or APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD." >&2
  exit 1
}

notarize_dmg() {
  local dmg_path="$1"
  local args

  echo "Submitting $dmg_path for notarization..."
  # shellcheck disable=SC2207
  args=($(notary_args))
  xcrun notarytool submit "$dmg_path" "${args[@]}" --wait
  xcrun stapler staple "$dmg_path"
  spctl --assess --type open --verbose=4 "$dmg_path" || true
}

build=true
sign=false
notarize=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      build=false
      ;;
    --sign)
      sign=true
      ;;
    --notarize)
      sign=true
      notarize=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "$(current_platform)" != "macos" ]]; then
  echo "macOS direct distribution packages must be built on macOS." >&2
  exit 1
fi

require_command hdiutil
if [[ "$sign" == true ]]; then
  require_command codesign
  require_command spctl
fi
if [[ "$notarize" == true ]]; then
  require_command xcrun
fi

cd "$ROOT_DIR"

if [[ "$build" == true ]]; then
  "$ROOT_DIR/scripts/build_desktop_release.sh" macos
fi

app_path="$(find_release_app)"
if [[ -z "$app_path" ]]; then
  echo "Could not find built macOS .app. Run scripts/build_desktop_release.sh macos first." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
version="$(app_version)"
dmg_path="$DIST_DIR/fetchdeck-$version-macos.dmg"

if [[ "$sign" == true ]]; then
  sign_app "$app_path"
fi

create_dmg "$app_path" "$dmg_path" "$APP_NAME $version"

if [[ "$sign" == true ]]; then
  sign_dmg "$dmg_path"
fi

if [[ "$notarize" == true ]]; then
  notarize_dmg "$dmg_path"
fi

echo "macOS direct distribution package: $dmg_path"

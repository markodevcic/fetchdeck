# Fetchdeck

A desktop-only Flutter app for managing yt-dlp downloads with a polished queue-based UI.

## Targets

- macOS
- Windows
- Linux

Web is intentionally skipped.

## Stack

- Flutter `3.44.1`
- FVM
- `shadcn_ui`
- `flutter_riverpod`
- `window_manager`
- `file_picker`
- `path_provider`
- `shared_preferences`

## Development

```bash
cd /Users/marko/Projects/yt_dlp_desktop
fvm flutter pub get
fvm flutter run -d macos
```

Useful checks:

```bash
fvm dart format .
fvm flutter analyze
fvm flutter test
```

Before a desktop release build, prepare only the current platform's bundled
tools and build through the release wrapper:

```bash
scripts/build_desktop_release.sh current
```

To build and create a distributable artifact in `dist/`:

```bash
scripts/package_desktop_release.sh current
```

For macOS direct distribution outside the Mac App Store, create a drag-to-
Applications DMG:

```bash
scripts/package_macos_direct.sh
```

For public distribution, sign and notarize with Developer ID:

```bash
export MACOS_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="fetchdeck-notary"
scripts/package_macos_direct.sh --notarize
```

Create the notary profile once with:

```bash
xcrun notarytool store-credentials fetchdeck-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Use `macos`, `windows`, or `linux` explicitly when needed. Flutter desktop
builds are host-specific, so build Windows on Windows and Linux on Linux or
matching CI runners.

Bundled tool binaries are intentionally not stored in Git. See
`assets/tools/README.md` for local tool preparation and
`THIRD_PARTY_NOTICES.md` for release licensing notes.

## Product Direction

Fetchdeck should keep yt-dlp as the download engine and focus the Flutter app on:

- URL intake and metadata preview
- Download queue
- Presets for common audio/video workflows
- Playlist handling
- Format selection
- Subtitle, thumbnail, metadata, and SponsorBlock options
- Tool health checks for yt-dlp, ffmpeg, and ffprobe
- Safe process execution with structured progress parsing
- Bundled platform tools with future in-app yt-dlp updates
- Runtime yt-dlp update checks with user-controlled install/skip

See `AGENTS.md` for implementation rules and architectural notes.

## Current Status

The app now performs the first real engine step:

- checks for `yt-dlp`, `ffmpeg`, and `ffprobe`
- shows tool health in the sidebar
- runs yt-dlp metadata analysis for pasted URLs
- parses title, source, thumbnail, duration, playlist count, and format count
- adds analyzed URLs to the queue
- lets the user choose an output folder
- starts yt-dlp downloads for analyzed queue items
- streams progress into queue rows
- supports cancelling active downloads
- supports retrying failed downloads
- supports a configurable concurrent download limit
- supports optional browser-cookie authentication for private or account-gated media
- persists output folder, selected preset, and last-used tool paths across launches
- persists analyzed, failed, and completed queue items to local JSON
- restores interrupted queued/downloading jobs as ready items on app launch
- restores interrupted analysis as failed with a clear error
- separates Downloads, Queue, and Library views:
  - Downloads: active/ready/failed work
  - Queue: every persisted job
  - Library: completed jobs
- supports row actions for retry/start, cancel, remove, and opening completed output folders
- confirms destructive history/queue removal actions
- records completed file path, size, started time, and completed time
- opens or reveals completed files from the Inspector
- adds a Settings view for manual `yt-dlp`, `ffmpeg`, and `ffprobe` paths
- supports re-checking tool availability from Settings
- supports bundled tool install into app support
- supports user-controlled yt-dlp update checks and installs
- adds a Presets view for inspecting and selecting built-in argument sets
- supports creating, saving, selecting, and deleting custom yt-dlp presets
- embeds each job's preset definition so older queue items keep working even if a custom preset is later deleted
- parses available yt-dlp formats into analyzed media
- lets users select a specific format per job from the Inspector
- groups formats into Combined, Video only, Audio only, and Other
- improves format labels with codecs, resolution, extension, and size
- persists selected format overrides per queue item
- uses the provided logo as the in-app brand mark and generated desktop app icons
- includes a release wrapper that prepares platform-specific tool assets before building
- includes a packaging wrapper that creates local release artifacts under `dist/`

Next planned slices: platform release signing/notarization, final manual QA,
and packaging/license review for each platform.

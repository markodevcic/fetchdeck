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
tools:

```bash
scripts/prepare_platform_tools.sh macos
fvm flutter build macos
```

Use `windows` or `linux` instead when building those targets.

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
- persists output folder, selected preset, and last-used tool paths across launches
- persists analyzed, failed, and completed queue items to local JSON
- restores interrupted downloads as ready items on app launch
- separates Downloads, Queue, and Library views:
  - Downloads: active/ready/failed work
  - Queue: every persisted job
  - Library: completed jobs
- supports row actions for retry/start, cancel, remove, and opening completed output folders
- adds a Settings view for manual `yt-dlp`, `ffmpeg`, and `ffprobe` paths
- supports re-checking tool availability from Settings
- adds a Presets view for inspecting and selecting built-in argument sets
- supports creating, saving, selecting, and deleting custom yt-dlp presets
- embeds each job's preset definition so older queue items keep working even if a custom preset is later deleted
- parses available yt-dlp formats into analyzed media
- lets users select a specific format per job from the Inspector
- groups formats into Combined, Video only, Audio only, and Other
- improves format labels with codecs, resolution, extension, and size
- persists selected format overrides per queue item

Next planned slices: preset editing, deeper format filters, and bundled tool management.

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

See `AGENTS.md` for implementation rules and architectural notes.

## Current Status

The app now performs the first real engine step:

- checks for `yt-dlp`, `ffmpeg`, and `ffprobe`
- shows tool health in the sidebar
- runs yt-dlp metadata analysis for pasted URLs
- parses title, source, thumbnail, duration, playlist count, and format count
- adds analyzed URLs to the queue

Actual downloads and progress parsing are the next planned slice.

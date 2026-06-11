# AGENTS.md

## Project

Fetchdeck is a desktop-only Flutter application that provides a polished UX over yt-dlp. The app should target macOS, Windows, and Linux only. Do not add web implementation or web-specific behavior unless explicitly requested later.

## Toolchain

- Use FVM for every Flutter/Dart command.
- Pinned Flutter SDK: `3.44.1`
- Preferred commands:
  - `fvm flutter pub get`
  - `fvm dart format .`
  - `fvm flutter analyze`
  - `fvm flutter test`
  - `fvm flutter run -d macos`
  - `fvm flutter build macos`
  - `fvm flutter build windows`
  - `fvm flutter build linux`

## UI

- Use `shadcn_ui` for the app shell and controls.
- Keep the UI dense, calm, and desktop-native: queue-first layout, left navigation, right inspector, compact toolbars.
- Prefer familiar icons from `lucide_icons_flutter`, which is already pulled in by `shadcn_ui`.
- Keep card radius at 8px or less.
- Avoid marketing/landing-page UI. The first screen should be the usable download workbench.

## yt-dlp Integration

Do not reimplement yt-dlp. The Flutter app should call yt-dlp/ffmpeg as bundled or user-configured desktop executables.

Use structured yt-dlp outputs:

- Metadata: `yt-dlp -J URL`
- Format listings: parse JSON metadata or use stable print templates.
- Progress: `--progress-template` with parseable fields.
- Avoid parsing ordinary human stdout because yt-dlp does not guarantee that text remains stable.

The engine layer should build argument lists, not shell strings. Use `Process.start(executable, args)` on desktop.

Current engine slice:

- `lib/services/tools/tool_discovery.dart` detects `yt-dlp`, `ffmpeg`, and `ffprobe` from PATH plus common platform paths.
- `lib/services/yt_dlp/yt_dlp_service.dart` runs metadata analysis with `yt-dlp -J --no-warnings --skip-download URL`.
- `lib/models/download_models.dart` holds the current `DownloadJob`, `DownloadPreset`, `DownloadStatus`, and `MediaInfo` types.
- Widget tests should use `FetchdeckApp(enableToolInspection: false)` so tests do not spawn real subprocesses.

Initial presets:

- MP3 320: `-f ba -x --audio-format mp3 --audio-quality 320K`
- Best audio original: `-f ba -x`
- Best MP4 up to 1080p: `-f bv*[height<=1080]+ba/b[height<=1080] --merge-output-format mp4`
- Best available video: `-f bv*+ba/b`

## Packaging Notes

- Bundle or locate yt-dlp, ffmpeg, and ffprobe per platform.
- Add a tool health check during app startup.
- Document license obligations before shipping. yt-dlp source is Unlicense, but official PyInstaller release binaries include GPLv3+ components. ffmpeg licensing depends on the build.
- macOS builds will eventually need signing/notarization and executable permission handling for bundled tools.

## Architecture Direction

Recommended structure for the next implementation pass:

```text
lib/
  app/
  features/downloads/
  features/presets/
  services/yt_dlp/
  services/tools/
  shared/ui/
```

Keep process execution, command argument construction, and parsing outside widgets. Widgets should consume typed state such as `DownloadJob`, `DownloadPreset`, `MediaInfo`, `FormatOption`, and `ProgressEvent`.

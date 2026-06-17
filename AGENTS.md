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

## Split Editor Playback

- Use `media_kit` with `media_kit_libs_audio` for desktop audio playback in the split editor.
- Call `MediaKit.ensureInitialized()` during app startup before creating players.
- Keep playback state in Riverpod application controllers, not widgets.
- `splitAudioAutoloadEnabledProvider` exists so unit/widget tests can disable native player loading. Override it to `false` in tests unless the test is intentionally exercising real media playback.
- The split editor uses marker timestamps as song-start positions. The `00:00` marker is required and represents the first generated segment.

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
- `YtDlpService.startDownload(...)` runs downloads with `Process.start`, `--newline`, and a `fetchdeck:` `--progress-template`.
- `lib/services/yt_dlp/yt_dlp_authentication.dart` models optional
  `--cookies-from-browser` authentication. When enabled, both metadata analysis
  and downloads must receive the same auth arguments so private/account-gated
  browser-playable media can be analyzed and downloaded.
- `lib/services/settings/app_settings_repository.dart` persists output folder, selected preset, and last-used tool paths through `shared_preferences`.
- `lib/services/queue/queue_repository.dart` persists analyzed/completed/failed jobs to `queue.json` under the app support directory.
- `lib/services/presets/custom_preset_repository.dart` persists custom presets to `custom_presets.json` under the app support directory.
- `lib/models/download_models.dart` holds the current `DownloadJob`, `DownloadPreset`, `DownloadStatus`, and `MediaInfo` types.
- Widget tests should use `FetchdeckApp(enableToolInspection: false)` so tests do not spawn real subprocesses.

Queue restore behavior:

- `downloading` jobs restore as `ready` with `Interrupted` text because the process is gone after restart.
- `queued` jobs restore as `ready` with `Interrupted` text because the scheduler state is gone after restart.
- `analyzing` jobs restore as `failed` because metadata analysis was interrupted.

Current navigation behavior:

- Downloads shows non-completed jobs: ready, failed, analyzing, downloading, queued.
- Queue shows every persisted job.
- Library shows completed jobs only.
- Settings shows manual tool path configuration for `yt-dlp`, `ffmpeg`, and `ffprobe`.
- Presets shows built-in and custom presets, descriptions, command summaries, and argument previews.
- Custom presets can be created, selected, persisted, and deleted.

Settings behavior:

- Choosing a tool path saves it immediately and re-runs tool discovery.
- Clearing a tool path removes the saved preference and re-runs auto-detection.
- Re-check uses saved/manual paths first, then PATH and common install folders.
- Browser cookies can be enabled in Settings. Persist the enabled flag and
  selected browser, and pass the resulting `YtDlpAuthentication` through
  WorkbenchActions into analysis and download controllers.
- yt-dlp update checks happen at startup after tool discovery and can also be
  triggered manually from Settings. Updates are user-controlled: show available
  versions, then install only after the user clicks Update.

Current row actions:

- Ready/failed rows use the download action to start or retry.
- Downloading rows use the stop action to cancel.
- Completed rows expose a folder action that opens the saved output folder.
- Non-running rows can be removed from the persisted queue.

Current format behavior:

- Metadata parsing stores yt-dlp format rows in `MediaInfo.formats`.
- The Inspector exposes a format picker for analyzed jobs when formats are available.
- Formats are grouped as Combined, Video only, Audio only, and Other.
- Format labels include id, group, extension, resolution, codecs, size, and note where available.
- Selecting a format persists `DownloadJob.selectedFormatId`.
- Downloads replace the preset's `-f/--format` value with the selected format while preserving other preset arguments.

Initial presets:

- MP3 320: `-f ba -x --audio-format mp3 --audio-quality 320K`
- Best audio original: `-f ba -x`
- Best MP4 up to 1080p: `-f bv*[height<=1080]+ba/b[height<=1080] --merge-output-format mp4`
- Best available video: `-f bv*+ba/b`

## Packaging Notes

- Bundle or locate yt-dlp, ffmpeg, and ffprobe per platform.
- Flutter bundles only `assets/tools/current/`. Before building, run
  `scripts/prepare_platform_tools.sh macos`, `windows`, or `linux` so the app
  includes only that platform's binaries.
- Prefer `scripts/build_desktop_release.sh current` for release builds. It
  prepares platform-specific tools, runs `fvm flutter pub get`, and builds the
  current desktop platform.
- Use `scripts/package_desktop_release.sh current` to build and produce a local
  distributable artifact under `dist/`.
- Use `scripts/package_macos_direct.sh` for macOS direct distribution outside
  the Mac App Store. It creates a drag-to-Applications DMG. Add `--sign` with
  `MACOS_CODESIGN_IDENTITY="Developer ID Application: ..."` for a signed local
  DMG, or `--notarize` with `NOTARY_PROFILE`/Apple credentials for a public
  notarized DMG.
- Flutter desktop builds are host-specific. Build macOS on macOS, Windows on
  Windows, and Linux on Linux or matching CI runners. Do not expect the local
  macOS machine to produce Windows/Linux release artifacts.
- Keep source binaries under `assets/tools/macos`, `assets/tools/windows`, and
  `assets/tools/linux`. Do not add those source folders to `pubspec.yaml`
  assets, or every platform build will include every binary.
- `assets/images/logo.png` is the source in-app brand asset. Platform icons are
  generated from the same logo into macOS `AppIcon.appiconset`, Windows
  `app_icon.ico`, and Linux `runner/resources/app_icon.png`.
- Add a tool health check during app startup.
- Document license obligations before shipping. yt-dlp source is Unlicense, but official PyInstaller release binaries include GPLv3+ components. ffmpeg licensing depends on the build.
- Keep `THIRD_PARTY_NOTICES.md` current with the exact binary sources and
  release requirements before distribution.
- macOS direct-download builds should not use the App Sandbox because Fetchdeck
  executes managed helper tools (`yt-dlp`, `ffmpeg`, `ffprobe`) from
  Application Support.
- macOS public builds need Developer ID signing, hardened runtime, notarization,
  and stapling. Use `scripts/package_macos_direct.sh --notarize`.

## Architecture Rules

Use Riverpod with a feature-first MVVM architecture. This is the required architecture for new code and refactors.

- Views are Flutter widgets only. They render state and forward user intent.
- ViewModels/controllers are Riverpod `Notifier` or `AsyncNotifier` classes under `features/<feature>/application/`.
- Domain models live under `features/<feature>/domain/` as migration proceeds.
- Repositories and platform/process adapters live under `features/<feature>/data/` or `core/` when shared.
- Services/repositories should be exposed through Riverpod providers. Widgets should not instantiate process, persistence, or platform services directly.
- Prefer immutable state objects for feature state: queue, downloads, presets, settings, and tool health.
- Keep yt-dlp process execution, command argument construction, file picking, folder reveal, persistence, and parsing outside presentation widgets.
- Use plain `flutter_riverpod` providers for now. Do not add Riverpod code generation unless the project explicitly decides to adopt it later.

Target structure:

```text
lib/
  app/
  features/downloads/
    domain/
    data/
    application/
    presentation/
  features/presets/
    domain/
    data/
    application/
    presentation/
  features/settings/
    domain/
    data/
    application/
    presentation/
  features/shell/
    application/
    presentation/
  core/
```

Current migration slice:

- `lib/features/shell/application/navigation_controller.dart` owns sidebar route state through Riverpod.
- `lib/features/downloads/application/queue_controller.dart` owns queue jobs, selected job id, visible queue filtering, queue mutation, and queue persistence through Riverpod.
- `main.dart` is temporarily still large while state is being moved feature by feature.
- Each new implementation step should move at least one state/process responsibility out of `main.dart` unless doing so would make the change riskier.

# Third-Party Notices

Fetchdeck uses external command-line tools for media extraction and conversion.
These tools are not reimplemented by Fetchdeck; the app executes bundled or
user-selected desktop binaries.

## yt-dlp

- Project: https://github.com/yt-dlp/yt-dlp
- Source license: Unlicense
- Script source: `scripts/download_tools.sh`
- Scripted release assets:
  - macOS: `yt-dlp_macos`
  - Windows: `yt-dlp.exe`
  - Linux: `yt-dlp_linux`
- Release binaries may include bundled Python/runtime components with additional
  licenses. Review the release artifact contents before shipping.

## FFmpeg / ffprobe

- Project: https://ffmpeg.org/
- Script source: `scripts/download_tools.sh`
- Scripted binary sources:
  - macOS: evermeet.cx FFmpeg and ffprobe releases
  - Windows: BtbN FFmpeg GPL builds
  - Linux: BtbN FFmpeg GPL builds
- License depends on the exact build configuration.
- Builds that include GPL components require GPL-compliant distribution.
- Builds that include nonfree components must not be redistributed as open
  source/free software without reviewing the terms.

## Release Requirements

Before distributing a Fetchdeck release:

- Record the exact yt-dlp, ffmpeg, and ffprobe versions used for each platform.
- Record the exact download URLs or artifact provenance for each binary.
- Include or link to applicable license texts for bundled command-line tools.
- Confirm whether the selected FFmpeg builds are LGPL, GPL, or nonfree.
- If shipping GPL FFmpeg builds, make the release GPL-compliant.
- If replacing the scripted binary sources, update this notice.

The local manifests under `assets/tools/<platform>/manifest.json` are version
hints for the app UI. They are not a substitute for release license review.

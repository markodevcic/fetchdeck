# Tool Assets

Large `yt-dlp`, `ffmpeg`, and `ffprobe` binaries are intentionally not stored
in Git.

Keep platform source folders locally:

- `assets/tools/macos/`
- `assets/tools/windows/`
- `assets/tools/linux/`

Before building, prepare the platform-specific bundle that Flutter includes:

```bash
scripts/prepare_platform_tools.sh macos
```

Use `windows` or `linux` for those release builds. The generated
`assets/tools/current/` binaries are ignored by Git; only `.gitkeep` is tracked.

For release builds, prefer the wrapper script:

```bash
scripts/build_desktop_release.sh current
```

To produce a local distributable under `dist/`, use:

```bash
scripts/package_desktop_release.sh current
```

Flutter desktop builds are host-specific, so build macOS on macOS, Windows on
Windows, and Linux on Linux or matching CI runners. The wrapper refuses
cross-platform builds so a release cannot accidentally bundle the wrong tools.

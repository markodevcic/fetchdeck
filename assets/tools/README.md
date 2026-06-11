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

enum ToolKind {
  ytDlp('yt-dlp'),
  ffmpeg('ffmpeg'),
  ffprobe('ffprobe');

  const ToolKind(this.label);

  final String label;
}

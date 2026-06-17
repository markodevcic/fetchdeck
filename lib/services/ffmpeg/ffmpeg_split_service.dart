import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FfmpegSplitService {
  const FfmpegSplitService({required this.executable});

  final String executable;

  Future<FfmpegSplitSession> startExport({
    required String sourceFilePath,
    required String outputFilePath,
    required String title,
    required Duration startTime,
    required Duration duration,
    required Duration fadeDuration,
  }) async {
    if (duration <= Duration.zero) {
      throw const FfmpegSplitException('Segment duration must be positive.');
    }

    final process = await Process.start(
      executable,
      buildArguments(
        sourceFilePath: sourceFilePath,
        outputFilePath: outputFilePath,
        title: title,
        startTime: startTime,
        duration: duration,
        fadeDuration: fadeDuration,
      ),
      runInShell: Platform.isWindows,
    );

    final stderr = StringBuffer();
    final stderrDone = Completer<void>();
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.write, onDone: stderrDone.complete);
    final progressController = StreamController<double>.broadcast();
    final stdoutDone = Completer<void>();
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final progress = FfmpegProgressParser.parseLine(
            line,
            duration: duration,
          );
          if (progress != null && !progressController.isClosed) {
            progressController.add(progress);
          }
        }, onDone: stdoutDone.complete);

    final completed = process.exitCode
        .then((exitCode) async {
          await stdoutDone.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
          await stderrDone.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
          await stdoutSubscription.cancel();
          await stderrSubscription.cancel();
          if (exitCode != 0) {
            throw FfmpegSplitException(_cleanError(stderr.toString()));
          }
          if (!progressController.isClosed) {
            progressController.add(1);
          }
        })
        .whenComplete(() async {
          if (!progressController.isClosed) {
            await progressController.close();
          }
        });

    return FfmpegSplitSession(
      process: process,
      progress: progressController.stream,
      completed: completed,
      onCancel: () {
        process.kill();
      },
    );
  }

  static List<String> buildArguments({
    required String sourceFilePath,
    required String outputFilePath,
    required String title,
    required Duration startTime,
    required Duration duration,
    required Duration fadeDuration,
  }) {
    return [
      '-y',
      '-hide_banner',
      '-nostats',
      '-progress',
      'pipe:1',
      '-ss',
      _seconds(startTime),
      '-i',
      sourceFilePath,
      '-t',
      _seconds(duration),
      '-vn',
      '-map_metadata',
      '-1',
      '-metadata',
      'title=$title',
      '-acodec',
      'libmp3lame',
      '-b:a',
      '320k',
      if (fadeDuration > Duration.zero) ...[
        '-af',
        _fadeFilter(duration: duration, fadeDuration: fadeDuration),
      ],
      outputFilePath,
    ];
  }

  static String _fadeFilter({
    required Duration duration,
    required Duration fadeDuration,
  }) {
    final safeFade = fadeDuration > duration ~/ 2
        ? duration ~/ 2
        : fadeDuration;
    final fadeSeconds = _seconds(safeFade);
    final outStart = duration - safeFade;
    return 'afade=t=in:st=0:d=$fadeSeconds,'
        'afade=t=out:st=${_seconds(outStart)}:d=$fadeSeconds';
  }

  static String _seconds(Duration duration) {
    return (duration.inMilliseconds / 1000).toStringAsFixed(3);
  }

  static String _cleanError(String stderr) {
    final lines = stderr
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return 'ffmpeg failed while exporting segment.';
    final excerpt = lines.length <= 4
        ? lines.join('\n')
        : lines.sublist(lines.length - 4).join('\n');
    return excerpt.length <= 700 ? excerpt : '${excerpt.substring(0, 699)}…';
  }
}

class FfmpegProgressParser {
  const FfmpegProgressParser._();

  static double? parseLine(String line, {required Duration duration}) {
    if (duration <= Duration.zero) return null;
    final separatorIndex = line.indexOf('=');
    if (separatorIndex == -1) return null;

    final key = line.substring(0, separatorIndex).trim();
    final value = line.substring(separatorIndex + 1).trim();
    final position = switch (key) {
      'out_time_ms' || 'out_time_us' => _durationFromMicroseconds(value),
      'out_time' => _durationFromTimestamp(value),
      _ => null,
    };
    if (position == null) return null;

    return (position.inMilliseconds / duration.inMilliseconds)
        .clamp(0, 1)
        .toDouble();
  }

  static Duration? _durationFromMicroseconds(String value) {
    final microseconds = int.tryParse(value);
    if (microseconds == null) return null;
    return Duration(microseconds: microseconds);
  }

  static Duration? _durationFromTimestamp(String value) {
    final parts = value.split(':');
    if (parts.length != 3) return null;

    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = double.tryParse(parts[2]);
    if (hours == null || minutes == null || seconds == null) return null;

    final wholeSeconds = seconds.truncate();
    final milliseconds = ((seconds - wholeSeconds) * 1000).round();
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: wholeSeconds,
      milliseconds: milliseconds,
    );
  }
}

class FfmpegSplitSession {
  const FfmpegSplitSession({
    required this.process,
    required this.progress,
    required this.completed,
    required this.onCancel,
  });

  final Process process;
  final Stream<double> progress;
  final Future<void> completed;
  final VoidCallback onCancel;

  void cancel() => onCancel();
}

typedef VoidCallback = void Function();

class FfmpegSplitException implements Exception {
  const FfmpegSplitException(this.message);

  final String message;

  @override
  String toString() => message;
}

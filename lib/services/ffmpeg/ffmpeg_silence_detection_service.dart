import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FfmpegSilenceDetectionService {
  const FfmpegSilenceDetectionService({required this.executable});

  final String executable;

  Future<List<Duration>> detectSongStarts({
    required String sourceFilePath,
    String noiseThreshold = '-35dB',
    Duration minimumSilence = const Duration(milliseconds: 1200),
    Duration duration = Duration.zero,
  }) async {
    final session = await startDetection(
      sourceFilePath: sourceFilePath,
      noiseThreshold: noiseThreshold,
      minimumSilence: minimumSilence,
      duration: duration,
    );
    return session.completed;
  }

  Future<FfmpegSilenceDetectionSession> startDetection({
    required String sourceFilePath,
    required String noiseThreshold,
    required Duration minimumSilence,
    required Duration duration,
  }) async {
    final process = await Process.start(
      executable,
      buildArguments(
        sourceFilePath: sourceFilePath,
        noiseThreshold: noiseThreshold,
        minimumSilence: minimumSilence,
      ),
      runInShell: Platform.isWindows,
    );

    final stderr = StringBuffer();
    final progressController = StreamController<double>.broadcast();
    final stderrDone = Completer<void>();
    final stdoutDone = Completer<void>();

    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.write, onDone: stderrDone.complete);
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final progress = FfmpegSilenceProgressParser.parseLine(
            line,
            duration: duration,
          );
          if (progress != null && !progressController.isClosed) {
            progressController.add(progress);
          }
        }, onDone: stdoutDone.complete);

    var wasCancelled = false;
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
          final output = stderr.toString();
          if (wasCancelled) {
            throw const FfmpegSilenceDetectionCancelledException();
          }
          if (exitCode != 0) {
            throw FfmpegSilenceDetectionException(_cleanError(output));
          }
          if (!progressController.isClosed) {
            progressController.add(1);
          }
          return FfmpegSilenceParser.parse(output);
        })
        .whenComplete(() async {
          if (!progressController.isClosed) {
            await progressController.close();
          }
        });

    return FfmpegSilenceDetectionSession(
      progress: progressController.stream,
      completed: completed,
      onCancel: () {
        wasCancelled = true;
        process.kill();
      },
    );
  }

  static List<String> buildArguments({
    required String sourceFilePath,
    required String noiseThreshold,
    required Duration minimumSilence,
  }) {
    return [
      '-hide_banner',
      '-nostats',
      '-progress',
      'pipe:1',
      '-i',
      sourceFilePath,
      '-af',
      'silencedetect=noise=$noiseThreshold:d=${_seconds(minimumSilence)}',
      '-f',
      'null',
      '-',
    ];
  }

  static String _seconds(Duration duration) {
    return (duration.inMilliseconds / 1000).toStringAsFixed(3);
  }

  static String _cleanError(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return 'ffmpeg failed while detecting silence.';
    final excerpt = lines.length <= 4
        ? lines.join('\n')
        : lines.sublist(lines.length - 4).join('\n');
    return excerpt.length <= 700 ? excerpt : '${excerpt.substring(0, 699)}…';
  }
}

class FfmpegSilenceParser {
  const FfmpegSilenceParser._();

  static final _silenceEndPattern = RegExp(
    r'silence_end:\s*([0-9]+(?:\.[0-9]+)?)',
  );

  static List<Duration> parse(String output) {
    return [
      for (final match in _silenceEndPattern.allMatches(output))
        if (double.tryParse(match.group(1) ?? '') case final seconds?)
          Duration(milliseconds: (seconds * 1000).round()),
    ];
  }
}

class FfmpegSilenceProgressParser {
  const FfmpegSilenceProgressParser._();

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

class FfmpegSilenceDetectionSession {
  const FfmpegSilenceDetectionSession({
    required this.progress,
    required this.completed,
    required this.onCancel,
  });

  final Stream<double> progress;
  final Future<List<Duration>> completed;
  final VoidCallback onCancel;

  void cancel() => onCancel();
}

typedef VoidCallback = void Function();

class FfmpegSilenceDetectionException implements Exception {
  const FfmpegSilenceDetectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FfmpegSilenceDetectionCancelledException
    extends FfmpegSilenceDetectionException {
  const FfmpegSilenceDetectionCancelledException()
    : super('Silence detection cancelled.');
}

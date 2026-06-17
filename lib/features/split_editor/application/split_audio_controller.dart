import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

final splitAudioControllerProvider =
    NotifierProvider<SplitAudioController, SplitAudioState>(
      SplitAudioController.new,
    );

final splitAudioAutoloadEnabledProvider = Provider<bool>((ref) => true);

class SplitAudioState {
  const SplitAudioState({
    this.sourceFilePath,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isLoading = false,
    this.error,
  });

  final String? sourceFilePath;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isLoading;
  final String? error;

  bool get hasSource => sourceFilePath != null && sourceFilePath!.isNotEmpty;

  SplitAudioState copyWith({
    String? sourceFilePath,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isLoading,
    String? error,
    bool clearSource = false,
    bool clearError = false,
  }) {
    return SplitAudioState(
      sourceFilePath: clearSource
          ? null
          : sourceFilePath ?? this.sourceFilePath,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class SplitAudioController extends Notifier<SplitAudioState> {
  Player? _player;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  bool _isDisposed = false;

  @override
  SplitAudioState build() {
    ref.onDispose(() {
      _isDisposed = true;
      _disposePlayer();
    });
    return const SplitAudioState();
  }

  Future<void> load(
    String? sourceFilePath, {
    Duration? fallbackDuration,
  }) async {
    await stop();
    if (sourceFilePath == null || sourceFilePath.trim().isEmpty) {
      state = SplitAudioState(
        duration: fallbackDuration ?? Duration.zero,
        error: 'Source file is not prepared yet.',
      );
      return;
    }

    final player = _player ??= Player();
    _bindPlayer(player);
    state = SplitAudioState(
      sourceFilePath: sourceFilePath,
      duration: fallbackDuration ?? Duration.zero,
      isLoading: true,
    );

    try {
      await player.open(Media(sourceFilePath), play: false);
      state = state.copyWith(isLoading: false, clearError: true);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load audio: $error',
      );
    }
  }

  Future<void> togglePlayback() async {
    final player = _player;
    if (player == null || !state.hasSource) return;
    if (state.isPlaying) {
      await pause();
    } else {
      await player.play();
    }
  }

  Future<void> pause() async {
    final player = _player;
    if (player == null || !state.hasSource) return;
    await player.pause();
    state = state.copyWith(isPlaying: false);
  }

  Future<void> seek(Duration position) async {
    final player = _player;
    if (player == null || !state.hasSource) return;
    final clamped = _clampPosition(position);
    await player.seek(clamped);
    state = state.copyWith(position: clamped);
  }

  Future<void> playFrom(Duration position) async {
    final player = _player;
    if (player == null || !state.hasSource) return;
    final clamped = _clampPosition(position);
    await player.seek(clamped);
    await player.play();
    state = state.copyWith(position: clamped, isPlaying: true);
  }

  Future<void> skipBy(Duration offset) {
    return seek(state.position + offset);
  }

  Future<void> stop() async {
    final player = _player;
    if (player == null) return;
    await player.pause();
    await player.seek(Duration.zero);
    state = state.copyWith(position: Duration.zero, isPlaying: false);
  }

  Future<void> release() async {
    _disposePlayer();
  }

  void _bindPlayer(Player player) {
    if (_positionSubscription != null) return;

    _positionSubscription = player.stream.position.listen((position) {
      if (_isDisposed) return;
      state = state.copyWith(position: _clampPosition(position));
    });
    _durationSubscription = player.stream.duration.listen((duration) {
      if (_isDisposed) return;
      state = state.copyWith(duration: duration);
    });
    _playingSubscription = player.stream.playing.listen((isPlaying) {
      if (_isDisposed) return;
      state = state.copyWith(isPlaying: isPlaying);
    });
  }

  Duration _clampPosition(Duration position) {
    if (position < Duration.zero) return Duration.zero;
    final duration = state.duration;
    if (duration > Duration.zero && position > duration) return duration;
    return position;
  }

  void _disposePlayer() {
    final player = _player;
    final positionSubscription = _positionSubscription;
    final durationSubscription = _durationSubscription;
    final playingSubscription = _playingSubscription;

    _player = null;
    _positionSubscription = null;
    _durationSubscription = null;
    _playingSubscription = null;

    unawaited(
      Future.wait<void>([
            if (positionSubscription != null) positionSubscription.cancel(),
            if (durationSubscription != null) durationSubscription.cancel(),
            if (playingSubscription != null) playingSubscription.cancel(),
          ])
          .then((_) async {
            if (player == null) return;
            await player.stop();
            await player.dispose();
          })
          .catchError((_) {}),
    );
  }
}

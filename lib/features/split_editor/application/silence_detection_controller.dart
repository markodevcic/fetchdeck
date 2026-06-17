import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/ffmpeg/ffmpeg_silence_detection_service.dart';
import '../../../services/tools/tool_discovery.dart';
import '../../settings/application/tool_controller.dart';
import '../../shell/application/status_controller.dart';
import 'split_editor_controller.dart';
import 'split_plan_builder.dart';

final silenceDetectionControllerProvider =
    NotifierProvider<SilenceDetectionController, SilenceDetectionState>(
      SilenceDetectionController.new,
    );

final silenceDetectionServiceProvider =
    Provider.family<FfmpegSilenceDetectionService, String>(
      (ref, executable) =>
          FfmpegSilenceDetectionService(executable: executable),
    );

class SilenceDetectionState {
  const SilenceDetectionState({
    this.isDetecting = false,
    this.progress = 0,
    this.noiseThreshold = '-35dB',
    this.minimumSilence = const Duration(milliseconds: 1200),
    this.candidates = const [],
    this.error,
  });

  final bool isDetecting;
  final double progress;
  final String noiseThreshold;
  final Duration minimumSilence;
  final List<SilenceDetectionCandidate> candidates;
  final String? error;

  bool get hasCandidates => candidates.isNotEmpty;
  int get selectedCandidateCount =>
      candidates.where((candidate) => candidate.isSelected).length;

  SilenceDetectionState copyWith({
    bool? isDetecting,
    double? progress,
    String? noiseThreshold,
    Duration? minimumSilence,
    List<SilenceDetectionCandidate>? candidates,
    String? error,
    bool clearError = false,
    bool clearCandidates = false,
  }) {
    return SilenceDetectionState(
      isDetecting: isDetecting ?? this.isDetecting,
      progress: progress ?? this.progress,
      noiseThreshold: noiseThreshold ?? this.noiseThreshold,
      minimumSilence: minimumSilence ?? this.minimumSilence,
      candidates: clearCandidates ? const [] : candidates ?? this.candidates,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class SilenceDetectionCandidate {
  const SilenceDetectionCandidate({
    required this.id,
    required this.position,
    this.isSelected = true,
  });

  final String id;
  final Duration position;
  final bool isSelected;

  SilenceDetectionCandidate copyWith({bool? isSelected}) {
    return SilenceDetectionCandidate(
      id: id,
      position: position,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

typedef SilenceDetectionStatusReporter = void Function(String message);

class SilenceDetectionController extends Notifier<SilenceDetectionState> {
  FfmpegSilenceDetectionSession? _activeSession;
  int _scanGeneration = 0;

  @override
  SilenceDetectionState build() {
    ref.onDispose(_cancelActiveSession);
    return const SilenceDetectionState();
  }

  void setNoiseThreshold(String noiseThreshold) {
    state = state.copyWith(noiseThreshold: noiseThreshold, clearError: true);
  }

  void setMinimumSilence(Duration minimumSilence) {
    state = state.copyWith(minimumSilence: minimumSilence, clearError: true);
  }

  Future<void> detect() {
    return detectWith(
      toolSet: ref.read(toolControllerProvider).toolSet,
      reportStatus: ref.read(statusControllerProvider.notifier).setMessage,
    );
  }

  Future<void> detectWith({
    required ToolSet toolSet,
    required SilenceDetectionStatusReporter reportStatus,
  }) async {
    if (state.isDetecting) return;

    final editorState = ref.read(splitEditorControllerProvider);
    final sourceFilePath = editorState.sourceFilePath;
    final ffmpegPath = toolSet.ffmpeg.path;
    if (!toolSet.ffmpeg.isAvailable || ffmpegPath == null) {
      _fail(
        'Cannot detect silence because ffmpeg was not found.',
        reportStatus,
      );
      return;
    }
    if (sourceFilePath == null || sourceFilePath.trim().isEmpty) {
      _fail('Prepare a split source before detecting silence.', reportStatus);
      return;
    }
    if (editorState.duration <= Duration.zero) {
      _fail(
        'Track duration is required before detecting silence.',
        reportStatus,
      );
      return;
    }

    _scanGeneration += 1;
    final generation = _scanGeneration;
    state = state.copyWith(
      isDetecting: true,
      progress: 0,
      clearError: true,
      clearCandidates: true,
    );
    reportStatus('Detecting silence gaps...');

    try {
      final session = await ref
          .read(silenceDetectionServiceProvider(ffmpegPath))
          .startDetection(
            sourceFilePath: sourceFilePath,
            noiseThreshold: state.noiseThreshold,
            minimumSilence: state.minimumSilence,
            duration: editorState.duration,
          );
      _activeSession = session;
      final progressSubscription = session.progress.listen((progress) {
        if (generation != _scanGeneration) return;
        state = state.copyWith(progress: progress.clamp(0, 1).toDouble());
      });
      final detected = await session.completed.whenComplete(
        progressSubscription.cancel,
      );
      if (generation != _scanGeneration) return;
      _activeSession = null;

      final candidates = _candidatesFrom(detected);
      if (candidates.isEmpty) {
        reportStatus('No usable silence gaps found.');
      } else {
        reportStatus(
          'Found ${candidates.length} possible cut${candidates.length == 1 ? '' : 's'}.',
        );
      }
      state = state.copyWith(
        isDetecting: false,
        progress: 1,
        candidates: candidates,
        clearError: true,
      );
    } on FfmpegSilenceDetectionCancelledException {
      if (generation != _scanGeneration) return;
      _activeSession = null;
      state = state.copyWith(isDetecting: false, progress: 0, clearError: true);
      reportStatus('Silence detection cancelled.');
    } on FfmpegSilenceDetectionException catch (error) {
      if (generation != _scanGeneration) return;
      _activeSession = null;
      _fail(error.message, reportStatus);
    } catch (error) {
      if (generation != _scanGeneration) return;
      _activeSession = null;
      _fail('Silence detection failed: $error', reportStatus);
    }
  }

  void cancelDetection() {
    _cancelActiveSession();
    if (state.isDetecting) {
      state = state.copyWith(isDetecting: false, progress: 0);
    }
  }

  void _cancelActiveSession() {
    _scanGeneration += 1;
    _activeSession?.cancel();
    _activeSession = null;
  }

  void toggleCandidate(String candidateId) {
    state = state.copyWith(
      candidates: [
        for (final candidate in state.candidates)
          candidate.id == candidateId
              ? candidate.copyWith(isSelected: !candidate.isSelected)
              : candidate,
      ],
      clearError: true,
    );
  }

  void removeCandidate(String candidateId) {
    state = state.copyWith(
      candidates: state.candidates
          .where((candidate) => candidate.id != candidateId)
          .toList(growable: false),
      clearError: true,
    );
  }

  void selectAllCandidates() {
    state = state.copyWith(
      candidates: [
        for (final candidate in state.candidates)
          candidate.copyWith(isSelected: true),
      ],
      clearError: true,
    );
  }

  void clearCandidates() {
    state = state.copyWith(clearCandidates: true, clearError: true);
  }

  void acceptSelectedCandidates({
    SilenceDetectionStatusReporter? reportStatus,
  }) {
    final selected = state.candidates
        .where((candidate) => candidate.isSelected)
        .map((candidate) => candidate.position)
        .toList(growable: false);
    if (selected.isEmpty) {
      final message = 'Select at least one detected cut to add.';
      state = state.copyWith(error: message);
      reportStatus?.call(message);
      return;
    }

    final added = ref
        .read(splitEditorControllerProvider.notifier)
        .addDetectedMarkers(selected);
    if (added == 0) {
      final message = 'No selected cuts can be added.';
      state = state.copyWith(error: message);
      reportStatus?.call(message);
      return;
    }

    state = state.copyWith(clearCandidates: true, clearError: true);
    reportStatus?.call('Added $added silence marker${added == 1 ? '' : 's'}.');
  }

  void acceptSelected() {
    acceptSelectedCandidates(
      reportStatus: ref.read(statusControllerProvider.notifier).setMessage,
    );
  }

  void _fail(String message, SilenceDetectionStatusReporter reportStatus) {
    state = state.copyWith(isDetecting: false, error: message);
    reportStatus(message);
  }

  List<SilenceDetectionCandidate> _candidatesFrom(List<Duration> positions) {
    final editorState = ref.read(splitEditorControllerProvider);
    final accepted = <Duration>[];

    for (final position in positions) {
      if (position <= Duration.zero || position >= editorState.duration) {
        continue;
      }
      final collidesWithExisting = editorState.markers.any(
        (marker) => _isTooClose(marker.position, position),
      );
      final collidesWithAccepted = accepted.any(
        (candidatePosition) => _isTooClose(candidatePosition, position),
      );
      if (collidesWithExisting || collidesWithAccepted) continue;
      accepted.add(position);
    }

    return [
      for (var index = 0; index < accepted.length; index += 1)
        SilenceDetectionCandidate(
          id: 'silence:${accepted[index].inMilliseconds}:$index',
          position: accepted[index],
        ),
    ];
  }

  bool _isTooClose(Duration a, Duration b) {
    final difference = a > b ? a - b : b - a;
    return difference < SplitPlanBuilder.minimumMarkerSpacing;
  }
}

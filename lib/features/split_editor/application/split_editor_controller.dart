import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/download_models.dart';
import '../../downloads/application/queue_controller.dart';
import '../../shell/application/status_controller.dart';
import 'split_audio_controller.dart';
import 'split_plan_builder.dart';

final splitEditorControllerProvider =
    NotifierProvider<SplitEditorController, SplitEditorState>(
      SplitEditorController.new,
    );

class SplitEditorState {
  const SplitEditorState({
    this.jobId,
    this.sourceFilePath,
    this.duration = Duration.zero,
    this.markers = const [],
    this.fadeDuration = Duration.zero,
    this.error,
  });

  final String? jobId;
  final String? sourceFilePath;
  final Duration duration;
  final List<SplitMarker> markers;
  final Duration fadeDuration;
  final String? error;

  bool get isOpen => jobId != null;
  SplitMarkerValidation get validation => SplitMarkerValidator.validate(this);
  bool get canApply =>
      jobId != null &&
      sourceFilePath != null &&
      sourceFilePath!.trim().isNotEmpty &&
      duration > Duration.zero &&
      markers.isNotEmpty &&
      validation.isValid;

  SplitEditorState copyWith({
    String? jobId,
    String? sourceFilePath,
    Duration? duration,
    List<SplitMarker>? markers,
    Duration? fadeDuration,
    String? error,
    bool clearError = false,
  }) {
    return SplitEditorState(
      jobId: jobId ?? this.jobId,
      sourceFilePath: sourceFilePath ?? this.sourceFilePath,
      duration: duration ?? this.duration,
      markers: markers ?? this.markers,
      fadeDuration: fadeDuration ?? this.fadeDuration,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class SplitEditorController extends Notifier<SplitEditorState> {
  @override
  SplitEditorState build() => const SplitEditorState();

  Future<void> open(DownloadJob job) async {
    final sourceFilePath = job.splitEditorSourcePath;
    final duration = job.mediaInfo?.duration ?? Duration.zero;
    final existingPlan = job.splitPlan;
    final markers = existingPlan?.markers ?? _defaultMarkers();

    state = SplitEditorState(
      jobId: job.id,
      sourceFilePath: sourceFilePath,
      duration: duration,
      markers: _sortedMarkers(markers),
      fadeDuration: existingPlan?.fadeDuration ?? Duration.zero,
    );
    if (ref.read(splitAudioAutoloadEnabledProvider)) {
      await ref
          .read(splitAudioControllerProvider.notifier)
          .load(sourceFilePath, fallbackDuration: duration);
    }
  }

  void close() {
    unawaited(ref.read(splitAudioControllerProvider.notifier).stop());
    state = const SplitEditorState();
  }

  void addMarker(Duration position) {
    if (!state.isOpen || state.duration <= Duration.zero) return;
    final clampedPosition = _clampPosition(position, state.duration);
    final nextIndex = state.markers.length + 1;
    final marker = SplitMarker(
      id: 'marker:${DateTime.now().microsecondsSinceEpoch}',
      position: clampedPosition,
      title: 'Track ${nextIndex.toString().padLeft(2, '0')}',
    );

    state = state.copyWith(
      markers: _sortedMarkers([...state.markers, marker]),
      clearError: true,
    );
  }

  int addDetectedMarkers(List<Duration> positions) {
    if (!state.isOpen || state.duration <= Duration.zero) return 0;

    final accepted = <Duration>[];
    for (final position in positions) {
      if (position <= Duration.zero || position >= state.duration) continue;
      final collidesWithExisting = state.markers.any(
        (marker) => _isTooClose(marker.position, position),
      );
      final collidesWithAccepted = accepted.any(
        (markerPosition) => _isTooClose(markerPosition, position),
      );
      if (collidesWithExisting || collidesWithAccepted) continue;
      accepted.add(position);
    }
    if (accepted.isEmpty) return 0;

    var nextIndex = state.markers.length + 1;
    final markers = [
      ...state.markers,
      for (final position in accepted) _detectedMarker(position, nextIndex++),
    ];
    state = state.copyWith(markers: _sortedMarkers(markers), clearError: true);
    return accepted.length;
  }

  void removeMarker(String markerId) {
    final marker = state.markers
        .where((candidate) => candidate.id == markerId)
        .firstOrNull;
    if (marker == null || marker.id == 'marker:0') return;

    state = state.copyWith(
      markers: state.markers
          .where((candidate) => candidate.id != markerId)
          .toList(growable: false),
      clearError: true,
    );
  }

  void renameMarker(String markerId, String title) {
    state = state.copyWith(
      markers: [
        for (final marker in state.markers)
          marker.id == markerId ? marker.copyWith(title: title) : marker,
      ],
      clearError: true,
    );
  }

  void moveMarker(String markerId, Duration position) {
    state = state.copyWith(
      markers: _sortedMarkers([
        for (final marker in state.markers)
          marker.id == markerId ? marker.copyWith(position: position) : marker,
      ]),
      clearError: true,
    );
  }

  void setFadeDuration(Duration fadeDuration) {
    state = state.copyWith(fadeDuration: fadeDuration, clearError: true);
  }

  bool apply() {
    final jobId = state.jobId;
    final sourceFilePath = state.sourceFilePath;
    if (jobId == null || sourceFilePath == null) return false;
    final validation = state.validation;
    if (!validation.isValid) {
      state = state.copyWith(error: validation.summary);
      return false;
    }

    try {
      final result = const SplitPlanBuilder().build(
        sourceFilePath: sourceFilePath,
        duration: state.duration,
        markers: state.markers,
        fadeDuration: state.fadeDuration,
        appliedAt: DateTime.now(),
      );
      ref
          .read(queueControllerProvider.notifier)
          .update(
            jobId,
            (job) => job.copyWith(
              splitPlan: result.plan,
              children: result.children,
              isExpanded: true,
            ),
          );
      ref
          .read(statusControllerProvider.notifier)
          .setMessage(
            'Created ${result.children.length} split segments. Select the segments and press Export to create files.',
          );
      close();
      return true;
    } on SplitPlanException catch (error) {
      state = state.copyWith(error: error.message);
      return false;
    }
  }

  List<SplitMarker> _defaultMarkers() {
    return const [
      SplitMarker(id: 'marker:0', position: Duration.zero, title: 'Track 01'),
    ];
  }

  Duration _clampPosition(Duration position, Duration duration) {
    if (position < Duration.zero) return Duration.zero;
    if (position >= duration) return duration - const Duration(seconds: 1);
    return position;
  }

  List<SplitMarker> _sortedMarkers(List<SplitMarker> markers) {
    return [...markers]..sort((a, b) => a.position.compareTo(b.position));
  }

  SplitMarker _detectedMarker(Duration position, int index) {
    return SplitMarker(
      id: 'marker:${DateTime.now().microsecondsSinceEpoch}:$index',
      position: position,
      title: 'Track ${index.toString().padLeft(2, '0')}',
    );
  }

  bool _isTooClose(Duration a, Duration b) {
    final difference = a > b ? a - b : b - a;
    return difference < SplitPlanBuilder.minimumMarkerSpacing;
  }
}

class SplitMarkerValidation {
  const SplitMarkerValidation({
    this.generalError,
    this.markerErrors = const {},
  });

  final String? generalError;
  final Map<String, String> markerErrors;

  bool get isValid => generalError == null && markerErrors.isEmpty;
  String? errorFor(String markerId) => markerErrors[markerId];
  String get summary =>
      generalError ?? markerErrors.values.firstOrNull ?? 'Invalid markers.';
}

class SplitMarkerValidator {
  const SplitMarkerValidator._();

  static SplitMarkerValidation validate(SplitEditorState state) {
    if (state.sourceFilePath == null || state.sourceFilePath!.trim().isEmpty) {
      return const SplitMarkerValidation(
        generalError: 'Source file is not prepared.',
      );
    }
    if (state.duration <= Duration.zero) {
      return const SplitMarkerValidation(
        generalError: 'Track duration must be greater than zero.',
      );
    }
    if (state.markers.isEmpty) {
      return const SplitMarkerValidation(
        generalError: 'Add at least one marker.',
      );
    }

    final errors = <String, String>{};
    final sorted = [...state.markers]
      ..sort((a, b) => a.position.compareTo(b.position));
    final positions = <int, String>{};

    for (final marker in sorted) {
      if (marker.title.trim().isEmpty) {
        errors[marker.id] = 'Song title is required.';
        continue;
      }
      if (marker.position < Duration.zero) {
        errors[marker.id] = 'Timestamp cannot be negative.';
        continue;
      }
      if (marker.position >= state.duration) {
        errors[marker.id] = 'Timestamp must be before the end.';
        continue;
      }
      final duplicateMarkerId = positions[marker.position.inMilliseconds];
      if (duplicateMarkerId != null) {
        errors[marker.id] = 'Another marker already uses this timestamp.';
        errors.putIfAbsent(
          duplicateMarkerId,
          () => 'Another marker already uses this timestamp.',
        );
        continue;
      }
      positions[marker.position.inMilliseconds] = marker.id;
    }

    for (var index = 1; index < sorted.length; index += 1) {
      final previous = sorted[index - 1];
      final current = sorted[index];
      if (current.position - previous.position <
          SplitPlanBuilder.minimumMarkerSpacing) {
        errors[current.id] =
            'Markers must be at least ${SplitPlanBuilder.minimumMarkerSpacing.inSeconds}s apart.';
        errors.putIfAbsent(
          previous.id,
          () =>
              'Markers must be at least ${SplitPlanBuilder.minimumMarkerSpacing.inSeconds}s apart.',
        );
      }
    }

    return SplitMarkerValidation(markerErrors: errors);
  }
}

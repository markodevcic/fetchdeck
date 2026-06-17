// ignore_for_file: sort_child_properties_last

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart' as forui;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';

import '../../../models/download_models.dart';
import '../application/silence_detection_controller.dart';
import '../application/split_audio_controller.dart';
import '../application/split_editor_controller.dart';

class SplitEditorDrawer extends ConsumerStatefulWidget {
  const SplitEditorDrawer({
    super.key,
    required this.job,
    required this.onClose,
    this.useSheetSurface = false,
  });

  final DownloadJob job;
  final VoidCallback onClose;
  final bool useSheetSurface;

  static const _fadeOptions = [
    Duration.zero,
    Duration(milliseconds: 100),
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
    Duration(seconds: 1),
  ];
  static const _scanPresets = [
    _SilenceScanPreset(
      label: 'Sensitive',
      noiseThreshold: '-32dB',
      minimumSilence: Duration(milliseconds: 450),
    ),
    _SilenceScanPreset(
      label: 'Balanced',
      noiseThreshold: '-35dB',
      minimumSilence: Duration(milliseconds: 1200),
    ),
    _SilenceScanPreset(
      label: 'Strict',
      noiseThreshold: '-30dB',
      minimumSilence: Duration(milliseconds: 1800),
    ),
    _SilenceScanPreset(
      label: 'Long gaps',
      noiseThreshold: '-35dB',
      minimumSilence: Duration(milliseconds: 2500),
    ),
  ];

  @override
  ConsumerState<SplitEditorDrawer> createState() => _SplitEditorDrawerState();

  static String _fadeLabel(Duration duration) {
    if (duration == Duration.zero) return 'Fade: Off';
    if (duration == const Duration(milliseconds: 100)) return 'Fade: Subtle';
    if (duration == const Duration(milliseconds: 250)) return 'Fade: Gentle';
    if (duration == const Duration(milliseconds: 500)) return 'Fade: Smooth';
    if (duration == const Duration(seconds: 1)) return 'Fade: Long';
    return 'Fade: Custom';
  }

  static int _scanPresetIndex(SilenceDetectionState state) {
    final index = _scanPresets.indexWhere(
      (preset) =>
          preset.noiseThreshold == state.noiseThreshold &&
          preset.minimumSilence == state.minimumSilence,
    );
    return index == -1 ? 1 : index;
  }
}

class _SplitEditorDrawerState extends ConsumerState<SplitEditorDrawer> {
  Duration? _reviewBackgroundPosition;
  String? _previewingMarkerId;
  Duration? _previewEndPosition;
  bool _previewSeekPending = false;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final state = ref.watch(splitEditorControllerProvider);
    final audioState = ref.watch(splitAudioControllerProvider);
    final silenceState = ref.watch(silenceDetectionControllerProvider);
    final controller = ref.read(splitEditorControllerProvider.notifier);
    final audioController = ref.read(splitAudioControllerProvider.notifier);
    final silenceController = ref.read(
      silenceDetectionControllerProvider.notifier,
    );
    final timelineDuration = audioState.duration > Duration.zero
        ? audioState.duration
        : state.duration;
    final isReviewingDetectedCuts = silenceState.hasCandidates;
    if (isReviewingDetectedCuts && _reviewBackgroundPosition == null) {
      _reviewBackgroundPosition = audioState.position;
    } else if (!isReviewingDetectedCuts && _reviewBackgroundPosition != null) {
      _reviewBackgroundPosition = null;
    }
    final mainTimelinePosition =
        _reviewBackgroundPosition ?? audioState.position;
    final mainPlaybackActive = audioState.isPlaying && !isReviewingDetectedCuts;
    final canAddMarker =
        state.duration > Duration.zero &&
        !_hasMarkerAtPlayhead(state, audioState.position);
    _pauseFinishedMarkerPreview(audioState);

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 520.0;
        final editorHeight = availableHeight.clamp(420.0, 520.0);

        return SizedBox(
          height: editorHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.useSheetSurface ? 0 : 18,
              widget.useSheetSurface ? 0 : 14,
              widget.useSheetSurface ? 0 : 18,
              widget.useSheetSurface ? 0 : 16,
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.scissors, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Split Editor',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.large,
                          ),
                        ),
                        _SplitIconButton(
                          icon: LucideIcons.x,
                          variant: _SplitIconButtonVariant.ghost,
                          onPressed: () => unawaited(_requestClose(state)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.small.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add cut points, name each segment, then apply them to export separate tracks.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.foreground.withValues(
                          alpha: 0.62,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _SplitIconButton(
                          icon: LucideIcons.rotateCcw,
                          variant: _SplitIconButtonVariant.outline,
                          onPressed: audioState.hasSource
                              ? () => audioController.skipBy(
                                  const Duration(seconds: -5),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        _SplitIconButton(
                          icon: mainPlaybackActive
                              ? LucideIcons.pause
                              : LucideIcons.play,
                          variant: mainPlaybackActive
                              ? _SplitIconButtonVariant.orange
                              : _SplitIconButtonVariant.blue,
                          onPressed:
                              audioState.hasSource && !audioState.isLoading
                              ? () {
                                  _clearMarkerPreview();
                                  unawaited(audioController.togglePlayback());
                                }
                              : null,
                        ),
                        const SizedBox(width: 8),
                        _SplitIconButton(
                          icon: LucideIcons.rotateCw,
                          variant: _SplitIconButtonVariant.outline,
                          onPressed: audioState.hasSource
                              ? () => audioController.skipBy(
                                  const Duration(seconds: 5),
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        _TimelineTimeLabel(
                          time: mainTimelinePosition,
                          duration: timelineDuration,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimelinePreview(
                            state: state,
                            position: mainTimelinePosition,
                            duration: timelineDuration,
                            onSeek: audioState.hasSource
                                ? (position) {
                                    _clearMarkerPreview();
                                    unawaited(audioController.seek(position));
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _TimelineTimeLabel(
                          time: timelineDuration,
                          duration: timelineDuration,
                        ),
                      ],
                    ),
                    if (audioState.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        audioState.error!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small.copyWith(
                          color: const Color(0xFFB91C1C),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Expanded(
                      child: _MarkerList(
                        state: state,
                        onSelectMarker: audioState.hasSource
                            ? (marker) => _selectMarkerRow(
                                marker,
                                state.markers,
                                timelineDuration,
                                audioController,
                              )
                            : null,
                        previewingMarkerId:
                            audioState.isPlaying && !isReviewingDetectedCuts
                            ? _previewingMarkerId
                            : null,
                        onPreviewToggle: audioState.hasSource
                            ? (marker) => _toggleMarkerPreview(
                                marker,
                                state.markers,
                                timelineDuration,
                                audioController,
                              )
                            : null,
                      ),
                    ),
                    if (state.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.error!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small.copyWith(
                          color: const Color(0xFFB91C1C),
                        ),
                      ),
                    ],
                    if (silenceState.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        silenceState.error!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small.copyWith(
                          color: const Color(0xFFB91C1C),
                        ),
                      ),
                    ],
                    if (silenceState.isDetecting) ...[
                      const SizedBox(height: 8),
                      _ScanProgress(value: silenceState.progress),
                    ],
                    const SizedBox(height: 12),
                    _SplitEditorActionBar(
                      state: state,
                      silenceState: silenceState,
                      onAddMarker: () =>
                          controller.addMarker(audioState.position),
                      canAddMarker: canAddMarker,
                      onDetectSilence: silenceController.detect,
                      onCancelDetection: silenceController.cancelDetection,
                      onScanPresetChanged: (preset) {
                        silenceController
                          ..setNoiseThreshold(preset.noiseThreshold)
                          ..setMinimumSilence(preset.minimumSilence);
                      },
                      onFadeChanged: controller.setFadeDuration,
                      onCancel: () => unawaited(_requestClose(state)),
                      onApply: state.canApply
                          ? () {
                              if (controller.apply()) widget.onClose();
                            }
                          : null,
                    ),
                  ],
                ),
                if (silenceState.hasCandidates)
                  Positioned.fill(
                    child: _SilenceDetectionReviewModal(
                      state: silenceState,
                      duration: timelineDuration,
                      isPlaying: audioState.isPlaying,
                      onToggle: silenceController.toggleCandidate,
                      onPreview: audioState.hasSource
                          ? (candidate, endPosition) {
                              _previewDetectedCut(
                                candidate,
                                endPosition,
                                audioController,
                              );
                            }
                          : null,
                      onPause: () {
                        _clearMarkerPreview();
                        unawaited(audioController.pause());
                      },
                      onSelectAll: silenceController.selectAllCandidates,
                      onClear: () {
                        unawaited(audioController.pause());
                        silenceController.clearCandidates();
                      },
                      onAccept: () {
                        unawaited(audioController.pause());
                        silenceController.acceptSelected();
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (widget.useSheetSurface) {
      return Material(color: Colors.transparent, child: content);
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Color.lerp(theme.colorScheme.background, Colors.black, 0.08),
          border: Border.all(color: theme.colorScheme.border),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: content,
      ),
    );
  }

  bool _hasMarkerAtPlayhead(SplitEditorState state, Duration playhead) {
    if (state.duration <= Duration.zero) return false;
    final clampedPlayhead = _clampMarkerPosition(playhead, state.duration);
    return state.markers.any(
      (marker) =>
          marker.position.inMilliseconds == clampedPlayhead.inMilliseconds,
    );
  }

  Future<void> _requestClose(SplitEditorState state) async {
    if (state.markers.length <= 1) {
      widget.onClose();
      return;
    }

    final confirmed = await forui.showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => forui.FDialog.adaptive(
        animation: animation,
        title: const Text('Close split editor?'),
        body: const Text(
          'The split markers you added will stay on this download, but this editing panel will close.',
        ),
        actions: [
          forui.FButton(
            variant: forui.FButtonVariant.destructive,
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('Close'),
          ),
          forui.FButton(
            variant: forui.FButtonVariant.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;
    widget.onClose();
  }

  Duration _clampMarkerPosition(Duration position, Duration duration) {
    if (position < Duration.zero) return Duration.zero;
    if (position >= duration) return duration - const Duration(seconds: 1);
    return position;
  }

  void _pauseFinishedMarkerPreview(SplitAudioState audioState) {
    final endPosition = _previewEndPosition;
    if (_previewingMarkerId == null ||
        endPosition == null ||
        _previewSeekPending ||
        !audioState.isPlaying ||
        audioState.position < endPosition) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final latestAudioState = ref.read(splitAudioControllerProvider);
      final latestEndPosition = _previewEndPosition;
      if (_previewingMarkerId == null ||
          latestEndPosition == null ||
          _previewSeekPending ||
          !latestAudioState.isPlaying ||
          latestAudioState.position < latestEndPosition) {
        return;
      }
      _clearMarkerPreview();
      unawaited(ref.read(splitAudioControllerProvider.notifier).pause());
    });
  }

  void _toggleMarkerPreview(
    SplitMarker marker,
    List<SplitMarker> markers,
    Duration duration,
    SplitAudioController audioController,
  ) {
    final sameMarker = _previewingMarkerId == marker.id;
    final audioState = ref.read(splitAudioControllerProvider);
    if (sameMarker && audioState.isPlaying) {
      _clearMarkerPreview();
      unawaited(audioController.pause());
      return;
    }

    final endPosition = _segmentEndFor(marker, markers, duration);
    setState(() {
      _previewingMarkerId = marker.id;
      _previewEndPosition = endPosition;
      _previewSeekPending = true;
      _reviewBackgroundPosition = null;
    });
    unawaited(
      audioController.playFrom(marker.position).whenComplete(() {
        if (!mounted || _previewingMarkerId != marker.id) return;
        setState(() {
          _previewSeekPending = false;
        });
      }),
    );
  }

  void _selectMarkerRow(
    SplitMarker marker,
    List<SplitMarker> markers,
    Duration duration,
    SplitAudioController audioController,
  ) {
    final audioState = ref.read(splitAudioControllerProvider);
    if (!audioState.isPlaying) {
      _clearMarkerPreview();
      unawaited(audioController.seek(marker.position));
      return;
    }

    final endPosition = _segmentEndFor(marker, markers, duration);
    setState(() {
      _previewingMarkerId = marker.id;
      _previewEndPosition = endPosition;
      _previewSeekPending = true;
      _reviewBackgroundPosition = null;
    });
    unawaited(
      audioController.playFrom(marker.position).whenComplete(() {
        if (!mounted || _previewingMarkerId != marker.id) return;
        setState(() {
          _previewSeekPending = false;
        });
      }),
    );
  }

  void _previewDetectedCut(
    SilenceDetectionCandidate candidate,
    Duration endPosition,
    SplitAudioController audioController,
  ) {
    setState(() {
      _previewingMarkerId = 'candidate:${candidate.id}';
      _previewEndPosition = endPosition;
      _previewSeekPending = true;
      _reviewBackgroundPosition = null;
    });
    unawaited(
      audioController.playFrom(candidate.position).whenComplete(() {
        if (!mounted || _previewingMarkerId != 'candidate:${candidate.id}') {
          return;
        }
        setState(() {
          _previewSeekPending = false;
        });
      }),
    );
  }

  Duration _segmentEndFor(
    SplitMarker marker,
    List<SplitMarker> markers,
    Duration duration,
  ) {
    final sorted = [...markers]
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final candidate in sorted) {
      if (candidate.position > marker.position) return candidate.position;
    }
    return duration;
  }

  void _clearMarkerPreview() {
    if (_previewingMarkerId == null && _previewEndPosition == null) return;
    setState(() {
      _previewingMarkerId = null;
      _previewEndPosition = null;
      _previewSeekPending = false;
    });
  }
}

class _SilenceScanPreset {
  const _SilenceScanPreset({
    required this.label,
    required this.noiseThreshold,
    required this.minimumSilence,
  });

  final String label;
  final String noiseThreshold;
  final Duration minimumSilence;

  String get selectLabel => 'Scan $label';
}

class _SplitEditorActionBar extends StatelessWidget {
  const _SplitEditorActionBar({
    required this.state,
    required this.silenceState,
    required this.onAddMarker,
    required this.canAddMarker,
    required this.onDetectSilence,
    required this.onCancelDetection,
    required this.onScanPresetChanged,
    required this.onFadeChanged,
    required this.onCancel,
    required this.onApply,
  });

  final SplitEditorState state;
  final SilenceDetectionState silenceState;
  final VoidCallback onAddMarker;
  final bool canAddMarker;
  final VoidCallback onDetectSilence;
  final VoidCallback onCancelDetection;
  final ValueChanged<_SilenceScanPreset> onScanPresetChanged;
  final ValueChanged<Duration> onFadeChanged;
  final VoidCallback onCancel;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final editControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedOpacity(
          opacity: canAddMarker ? 1 : 0.42,
          duration: const Duration(milliseconds: 140),
          child: forui.FButton(
            variant: forui.FButtonVariant.outline,
            size: forui.FButtonSizeVariant.sm,
            onPress: canAddMarker ? onAddMarker : null,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.plus, size: 15),
                SizedBox(width: 6),
                Text('Add Marker'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        forui.FButton(
          variant: forui.FButtonVariant.outline,
          size: forui.FButtonSizeVariant.sm,
          onPress: silenceState.isDetecting
              ? onCancelDetection
              : state.sourceFilePath != null && state.duration > Duration.zero
              ? onDetectSilence
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                silenceState.isDetecting ? LucideIcons.x : LucideIcons.search,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(silenceState.isDetecting ? 'Cancel' : 'Detect'),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 160,
          child: forui.FSelect<int>.rich(
            enabled: !silenceState.isDetecting,
            control: forui.FSelectControl.lifted(
              value: SplitEditorDrawer._scanPresetIndex(silenceState),
              onChange: (value) {
                if (value != null) {
                  onScanPresetChanged(SplitEditorDrawer._scanPresets[value]);
                }
              },
            ),
            format: (value) =>
                SplitEditorDrawer._scanPresets[value].selectLabel,
            children: [
              for (
                var index = 0;
                index < SplitEditorDrawer._scanPresets.length;
                index++
              )
                forui.FSelectItem<int>(
                  value: index,
                  title: Text(
                    SplitEditorDrawer._scanPresets[index].selectLabel,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 132,
          child: forui.FSelect<Duration>.rich(
            control: forui.FSelectControl.lifted(
              value: state.fadeDuration,
              onChange: (value) {
                if (value != null) onFadeChanged(value);
              },
            ),
            format: SplitEditorDrawer._fadeLabel,
            children: [
              for (final option in SplitEditorDrawer._fadeOptions)
                forui.FSelectItem<Duration>(
                  value: option,
                  title: Text(SplitEditorDrawer._fadeLabel(option)),
                ),
            ],
          ),
        ),
      ],
    );

    final commitControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        forui.FButton(
          variant: forui.FButtonVariant.outline,
          size: forui.FButtonSizeVariant.sm,
          onPress: onCancel,
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        forui.FButton(
          size: forui.FButtonSizeVariant.sm,
          onPress: onApply,
          child: const Text('Apply'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: editControls,
              ),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: commitControls),
            ],
          );
        }

        return Row(children: [editControls, const Spacer(), commitControls]);
      },
    );
  }
}

class _ScanProgress extends StatelessWidget {
  const _ScanProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final clampedValue = value.clamp(0, 1).toDouble();

    return Row(
      children: [
        Text('Scanning audio', style: theme.textTheme.small),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(color: theme.colorScheme.muted),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: clampedValue),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedValue, _) {
                      return FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: animatedValue <= 0 ? 0.04 : animatedValue,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('${(clampedValue * 100).round()}%', style: theme.textTheme.muted),
      ],
    );
  }
}

class _SilenceDetectionReviewModal extends StatefulWidget {
  const _SilenceDetectionReviewModal({
    required this.state,
    required this.duration,
    required this.isPlaying,
    required this.onToggle,
    required this.onPreview,
    required this.onPause,
    required this.onSelectAll,
    required this.onClear,
    required this.onAccept,
  });

  final SilenceDetectionState state;
  final Duration duration;
  final bool isPlaying;
  final ValueChanged<String> onToggle;
  final void Function(
    SilenceDetectionCandidate candidate,
    Duration endPosition,
  )?
  onPreview;
  final VoidCallback onPause;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onAccept;

  @override
  State<_SilenceDetectionReviewModal> createState() =>
      _SilenceDetectionReviewModalState();
}

class _SilenceDetectionReviewModalState
    extends State<_SilenceDetectionReviewModal> {
  String? previewingCandidateId;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      color: Colors.black.withValues(alpha: 0.38),
      child: Center(
        child: forui.FDialog.raw(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 380),
          builder: (context, style) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.searchCheck, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Review Detected Cuts',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.large,
                        ),
                      ),
                      _SplitIconButton(
                        icon: LucideIcons.x,
                        variant: _SplitIconButtonVariant.ghost,
                        onPressed: _clearAndPause,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.state.selectedCandidateCount}/${widget.state.candidates.length} cuts selected',
                    style: theme.textTheme.muted,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 230,
                    child: ListView.separated(
                      itemCount: widget.state.candidates.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final candidate = widget.state.candidates[index];
                        final isPreviewing =
                            previewingCandidateId == candidate.id &&
                            widget.isPlaying;
                        return _DetectionCandidateRow(
                          candidate: candidate,
                          index: index,
                          isPreviewing: isPreviewing,
                          onToggle: () => widget.onToggle(candidate.id),
                          onPreviewToggle: widget.onPreview == null
                              ? null
                              : () => _togglePreview(candidate),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      forui.FButton(
                        variant: forui.FButtonVariant.outline,
                        size: forui.FButtonSizeVariant.sm,
                        onPress: widget.onSelectAll,
                        child: const Text('Select All'),
                      ),
                      const SizedBox(width: 8),
                      forui.FButton(
                        variant: forui.FButtonVariant.outline,
                        size: forui.FButtonSizeVariant.sm,
                        onPress: _clearAndPause,
                        child: const Text('Discard'),
                      ),
                      const SizedBox(width: 8),
                      forui.FButton(
                        size: forui.FButtonSizeVariant.sm,
                        onPress: widget.state.selectedCandidateCount > 0
                            ? _acceptAndPause
                            : null,
                        child: const Text('Add Selected'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _togglePreview(SilenceDetectionCandidate candidate) {
    if (previewingCandidateId == candidate.id && widget.isPlaying) {
      widget.onPause();
      return;
    }
    setState(() => previewingCandidateId = candidate.id);
    widget.onPreview?.call(candidate, _candidateEndFor(candidate));
  }

  Duration _candidateEndFor(SilenceDetectionCandidate candidate) {
    final sorted = [...widget.state.candidates]
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final next in sorted) {
      if (next.position > candidate.position) return next.position;
    }
    return widget.duration;
  }

  void _clearAndPause() {
    widget.onPause();
    widget.onClear();
  }

  void _acceptAndPause() {
    widget.onPause();
    widget.onAccept();
  }
}

class _DetectionCandidateRow extends StatelessWidget {
  const _DetectionCandidateRow({
    required this.candidate,
    required this.index,
    required this.isPreviewing,
    required this.onToggle,
    required this.onPreviewToggle,
  });

  final SilenceDetectionCandidate candidate;
  final int index;
  final bool isPreviewing;
  final VoidCallback onToggle;
  final VoidCallback? onPreviewToggle;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final selectedColor = candidate.isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: candidate.isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.10)
              : theme.colorScheme.muted.withValues(alpha: 0.24),
          border: Border.all(
            color: candidate.isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.62)
                : theme.colorScheme.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _SplitIconButton(
              icon: isPreviewing ? LucideIcons.pause : LucideIcons.play,
              variant: isPreviewing
                  ? _SplitIconButtonVariant.orange
                  : _SplitIconButtonVariant.blue,
              size: 30,
              iconSize: 15,
              onPressed: onPreviewToggle,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Cut ${index + 1} at ${_formatTimestamp(candidate.position)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.small.copyWith(
                  color: candidate.isSelected
                      ? theme.colorScheme.foreground
                      : theme.colorScheme.mutedForeground,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 20,
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  candidate.isSelected
                      ? LucideIcons.squareCheckBig
                      : LucideIcons.square,
                  size: 17,
                  color: selectedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkerList extends ConsumerStatefulWidget {
  const _MarkerList({
    required this.state,
    this.onSelectMarker,
    this.previewingMarkerId,
    this.onPreviewToggle,
  });

  final SplitEditorState state;
  final ValueChanged<SplitMarker>? onSelectMarker;
  final String? previewingMarkerId;
  final ValueChanged<SplitMarker>? onPreviewToggle;

  @override
  ConsumerState<_MarkerList> createState() => _MarkerListState();
}

class _MarkerListState extends ConsumerState<_MarkerList> {
  final outgoingMarkers = <_OutgoingMarker>[];

  @override
  void didUpdateWidget(covariant _MarkerList oldWidget) {
    super.didUpdateWidget(oldWidget);

    final currentIds = widget.state.markers.map((marker) => marker.id).toSet();
    for (var index = 0; index < oldWidget.state.markers.length; index += 1) {
      final marker = oldWidget.state.markers[index];
      if (!currentIds.contains(marker.id) &&
          outgoingMarkers.every(
            (outgoing) => outgoing.marker.id != marker.id,
          )) {
        outgoingMarkers.add(
          _OutgoingMarker(
            marker: marker,
            index: index,
            error: oldWidget.state.validation.errorFor(marker.id),
          ),
        );
      }
    }

    if (outgoingMarkers.any((marker) => !marker.removing)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          for (final marker in outgoingMarkers) {
            marker.removing = true;
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final controller = ref.read(splitEditorControllerProvider.notifier);
    final markers = widget.state.markers;
    final validation = widget.state.validation;

    if (markers.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('No markers yet.', style: theme.textTheme.muted),
      );
    }

    final entries = [
      for (final marker in markers)
        _MarkerListEntry.current(
          marker: marker,
          error: validation.errorFor(marker.id),
        ),
    ];
    for (final outgoing in outgoingMarkers) {
      final insertIndex = outgoing.index.clamp(0, entries.length);
      entries.insert(insertIndex, _MarkerListEntry.outgoing(outgoing));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _AnimatedMarkerRow(
          key: ValueKey(entry.marker.id),
          visible: !entry.removing,
          onRemoved: entry.outgoing == null
              ? null
              : () {
                  if (!mounted) return;
                  setState(() {
                    outgoingMarkers.remove(entry.outgoing);
                  });
                },
          child: _MarkerRow(
            marker: entry.marker,
            endPosition: _segmentEndFor(entry.marker, markers),
            duration: widget.state.duration,
            error: entry.error,
            canRemove: entry.marker.id != 'marker:0' && !entry.removing,
            isPreviewing: widget.previewingMarkerId == entry.marker.id,
            onPreviewToggle: widget.onPreviewToggle == null
                ? null
                : () => widget.onPreviewToggle!(entry.marker),
            onSelect: widget.onSelectMarker == null
                ? null
                : () => widget.onSelectMarker!(entry.marker),
            onMove: (position) =>
                controller.moveMarker(entry.marker.id, position),
            onRename: (title) =>
                controller.renameMarker(entry.marker.id, title),
            onRemove: () => controller.removeMarker(entry.marker.id),
          ),
        );
      },
    );
  }

  Duration _segmentEndFor(SplitMarker marker, List<SplitMarker> markers) {
    final sorted = [...markers]
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final candidate in sorted) {
      if (candidate.position > marker.position) return candidate.position;
    }
    return widget.state.duration;
  }
}

class _OutgoingMarker {
  _OutgoingMarker({
    required this.marker,
    required this.index,
    required this.error,
  });

  final SplitMarker marker;
  final int index;
  final String? error;
  bool removing = false;
}

class _MarkerListEntry {
  const _MarkerListEntry._({
    required this.marker,
    required this.error,
    required this.removing,
    this.outgoing,
  });

  factory _MarkerListEntry.current({
    required SplitMarker marker,
    required String? error,
  }) {
    return _MarkerListEntry._(marker: marker, error: error, removing: false);
  }

  factory _MarkerListEntry.outgoing(_OutgoingMarker outgoing) {
    return _MarkerListEntry._(
      marker: outgoing.marker,
      error: outgoing.error,
      removing: outgoing.removing,
      outgoing: outgoing,
    );
  }

  final SplitMarker marker;
  final String? error;
  final bool removing;
  final _OutgoingMarker? outgoing;
}

class _AnimatedMarkerRow extends StatefulWidget {
  const _AnimatedMarkerRow({
    super.key,
    required this.visible,
    required this.child,
    this.onRemoved,
  });

  final bool visible;
  final Widget child;
  final VoidCallback? onRemoved;

  @override
  State<_AnimatedMarkerRow> createState() => _AnimatedMarkerRowState();
}

class _AnimatedMarkerRowState extends State<_AnimatedMarkerRow> {
  static const duration = Duration(milliseconds: 180);

  @override
  void didUpdateWidget(covariant _AnimatedMarkerRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible && !widget.visible) {
      Future<void>.delayed(duration, () {
        if (mounted) widget.onRemoved?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedOpacity(
          duration: duration,
          curve: Curves.easeOutCubic,
          opacity: widget.visible ? 1 : 0,
          child: widget.visible ? widget.child : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _MarkerRow extends StatelessWidget {
  const _MarkerRow({
    required this.marker,
    required this.endPosition,
    required this.duration,
    required this.error,
    required this.canRemove,
    required this.isPreviewing,
    required this.onMove,
    required this.onRename,
    required this.onRemove,
    this.onSelect,
    this.onPreviewToggle,
  });

  final SplitMarker marker;
  final Duration endPosition;
  final Duration duration;
  final String? error;
  final bool canRemove;
  final bool isPreviewing;
  final ValueChanged<Duration> onMove;
  final ValueChanged<String> onRename;
  final VoidCallback onRemove;
  final VoidCallback? onSelect;
  final VoidCallback? onPreviewToggle;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return MouseRegion(
      cursor: onSelect == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isPreviewing
                ? theme.colorScheme.primary.withValues(alpha: 0.11)
                : theme.colorScheme.muted.withValues(alpha: 0.16),
            border: Border.all(
              color: isPreviewing
                  ? theme.colorScheme.primary.withValues(alpha: 0.58)
                  : theme.colorScheme.border.withValues(alpha: 0.72),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _SplitIconButton(
                    icon: isPreviewing ? LucideIcons.pause : LucideIcons.play,
                    variant: isPreviewing
                        ? _SplitIconButtonVariant.orange
                        : _SplitIconButtonVariant.blue,
                    size: 34,
                    iconSize: 15,
                    onPressed: onPreviewToggle,
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 158,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 76,
                          child: marker.position == Duration.zero
                              ? _ReadonlyMarkerTimestamp(marker: marker)
                              : _MarkerTimestampField(
                                  marker: marker,
                                  duration: duration,
                                  onChanged: onMove,
                                ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '/ ${_formatTimestamp(endPosition)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.small.copyWith(
                              color: theme.colorScheme.mutedForeground,
                              fontSize: 11,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _MarkerTitleField(
                        marker: marker,
                        onChanged: onRename,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Visibility(
                    visible: canRemove,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: _SplitIconButton(
                      icon: LucideIcons.trash2,
                      variant: _SplitIconButtonVariant.ghost,
                      onPressed: onRemove,
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 208),
                  child: Text(
                    error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.small.copyWith(
                      color: const Color(0xFFB91C1C),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadonlyMarkerTimestamp extends StatelessWidget {
  const _ReadonlyMarkerTimestamp({required this.marker});

  final SplitMarker marker;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      height: 40,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _formatTimestamp(marker.position),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.small,
      ),
    );
  }
}

class _MarkerTimestampField extends StatefulWidget {
  const _MarkerTimestampField({
    required this.marker,
    required this.duration,
    required this.onChanged,
  });

  final SplitMarker marker;
  final Duration duration;
  final ValueChanged<Duration> onChanged;

  @override
  State<_MarkerTimestampField> createState() => _MarkerTimestampFieldState();
}

class _MarkerTimestampFieldState extends State<_MarkerTimestampField> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: _formatTimestamp(widget.marker.position),
    );
  }

  @override
  void didUpdateWidget(covariant _MarkerTimestampField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _formatTimestamp(widget.marker.position);
    if (oldWidget.marker.id != widget.marker.id ||
        oldWidget.marker.position != widget.marker.position) {
      controller.text = nextText;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return forui.FTextField(
      control: forui.FTextFieldControl.managed(controller: controller),
      hint: '0:00',
      onSubmit: (_) => _commit(),
    );
  }

  void _commit() {
    final parsed = _parseTimestamp(controller.text);
    if (parsed == null) {
      controller.text = _formatTimestamp(widget.marker.position);
      return;
    }
    widget.onChanged(parsed);
  }
}

class _MarkerTitleField extends StatefulWidget {
  const _MarkerTitleField({required this.marker, required this.onChanged});

  final SplitMarker marker;
  final ValueChanged<String> onChanged;

  @override
  State<_MarkerTitleField> createState() => _MarkerTitleFieldState();
}

class _MarkerTitleFieldState extends State<_MarkerTitleField> {
  late final TextEditingController controller;
  var syncingTitleFromWidget = false;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.marker.title);
    controller.addListener(_handleTitleChanged);
  }

  @override
  void didUpdateWidget(covariant _MarkerTitleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marker.id != widget.marker.id ||
        widget.marker.title != controller.text) {
      syncingTitleFromWidget = true;
      controller.text = widget.marker.title;
      syncingTitleFromWidget = false;
    }
  }

  @override
  void dispose() {
    controller.removeListener(_handleTitleChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return forui.FTextField(
      control: forui.FTextFieldControl.managed(controller: controller),
      hint: 'Song title',
    );
  }

  void _handleTitleChanged() {
    if (syncingTitleFromWidget) return;
    widget.onChanged(controller.text);
  }
}

class _TimelinePreview extends StatelessWidget {
  const _TimelinePreview({
    required this.state,
    required this.position,
    required this.duration,
    this.onSeek,
  });

  final SplitEditorState state;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final timeline = Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.muted,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _positionRatio(position, duration),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _markerLeft(position, duration, constraints.maxWidth),
                child: Container(
                  width: 6,
                  height: 18,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.foreground,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              for (final marker in state.markers)
                Positioned(
                  left: _markerLeft(
                    marker.position,
                    duration,
                    constraints.maxWidth,
                  ),
                  child: Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.background.withValues(
                            alpha: 0.85,
                          ),
                          blurRadius: 0,
                          spreadRadius: 1.5,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );

          if (onSeek == null) return timeline;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _seekFromOffset(details.localPosition.dx, constraints.maxWidth),
            onHorizontalDragStart: (details) =>
                _seekFromOffset(details.localPosition.dx, constraints.maxWidth),
            onHorizontalDragUpdate: (details) =>
                _seekFromOffset(details.localPosition.dx, constraints.maxWidth),
            child: timeline,
          );
        },
      ),
    );
  }

  double _positionRatio(Duration position, Duration duration) {
    if (duration <= Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds)
        .clamp(0, 1)
        .toDouble();
  }

  double _markerLeft(Duration position, Duration duration, double width) {
    if (duration <= Duration.zero || width <= 0) return 0;
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    return (ratio.clamp(0, 1) * width).toDouble();
  }

  void _seekFromOffset(double dx, double width) {
    if (duration <= Duration.zero || width <= 0) return;
    final ratio = (dx / width).clamp(0, 1).toDouble();
    onSeek!(Duration(milliseconds: (duration.inMilliseconds * ratio).round()));
  }
}

class _TimelineTimeLabel extends StatelessWidget {
  const _TimelineTimeLabel({required this.time, required this.duration});

  final Duration time;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final hasHours = duration.inHours > 0 || time.inHours > 0;

    return SizedBox(
      width: hasHours ? 74 : 48,
      child: Text(
        _formatTimestamp(time),
        textAlign: TextAlign.center,
        style: theme.textTheme.small.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

enum _SplitIconButtonVariant { ghost, outline, blue, orange }

class _SplitIconButton extends StatelessWidget {
  const _SplitIconButton({
    required this.icon,
    required this.onPressed,
    this.variant = _SplitIconButtonVariant.ghost,
    this.size = 32,
    this.iconSize = 16,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final _SplitIconButtonVariant variant;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final colors = switch (variant) {
      _SplitIconButtonVariant.blue => _SplitIconButtonColors(
        background: const Color(0xFF2563EB),
        hover: const Color(0xFF1D4ED8),
        pressed: const Color(0xFF1E40AF),
        foreground: Colors.white,
      ),
      _SplitIconButtonVariant.orange => _SplitIconButtonColors(
        background: const Color(0xFFF97316),
        hover: const Color(0xFFEA580C),
        pressed: const Color(0xFFC2410C),
        foreground: Colors.white,
      ),
      _ => null,
    };

    return SizedBox.square(
      dimension: size,
      child: forui.FButton.icon(
        variant: switch (variant) {
          _SplitIconButtonVariant.outline => forui.FButtonVariant.outline,
          _ => forui.FButtonVariant.ghost,
        },
        size: forui.FButtonSizeVariant.sm,
        onPress: enabled ? onPressed : null,
        style: colors == null
            ? _splitPlainIconButtonStyle
            : _splitColoredIconButtonStyle(
                backgroundColor: enabled
                    ? colors.background
                    : colors.background.withValues(alpha: 0.34),
                hoverBackgroundColor: colors.hover,
                pressedBackgroundColor: colors.pressed,
              ),
        child: Icon(icon, size: iconSize, color: colors?.foreground),
      ),
    );
  }
}

class _SplitIconButtonColors {
  const _SplitIconButtonColors({
    required this.background,
    required this.hover,
    required this.pressed,
    required this.foreground,
  });

  final Color background;
  final Color hover;
  final Color pressed;
  final Color foreground;
}

const _splitPlainIconButtonStyle = forui.FButtonStyleDelta.delta(
  iconContentStyle: forui.FButtonIconContentStyleDelta.delta(
    padding: forui.EdgeInsetsGeometryDelta.value(EdgeInsets.all(7)),
  ),
);

forui.FButtonStyleDelta _splitColoredIconButtonStyle({
  required Color backgroundColor,
  required Color hoverBackgroundColor,
  required Color pressedBackgroundColor,
}) {
  return forui.FButtonStyleDelta.delta(
    iconContentStyle: const forui.FButtonIconContentStyleDelta.delta(
      padding: forui.EdgeInsetsGeometryDelta.value(EdgeInsets.all(7)),
    ),
    decoration: forui.FVariantsDelta.delta([
      forui.FVariantOperation.base(
        forui.DecorationDelta.value(
          BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      forui.FVariantOperation.exact(
        {forui.FTappableVariantConstraint.hovered},
        forui.DecorationDelta.value(
          BoxDecoration(
            color: hoverBackgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      forui.FVariantOperation.exact(
        {forui.FTappableVariantConstraint.pressed},
        forui.DecorationDelta.value(
          BoxDecoration(
            color: pressedBackgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    ]),
  );
}

String _formatTimestamp(Duration duration) {
  if (duration <= Duration.zero) return '00:00';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

Duration? _parseTimestamp(String value) {
  final parts = value.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final numbers = parts.map(int.tryParse).toList(growable: false);
  if (numbers.any((part) => part == null || part < 0)) return null;

  final hours = parts.length == 3 ? numbers[0]! : 0;
  final minutes = parts.length == 3 ? numbers[1]! : numbers[0]!;
  final seconds = parts.length == 3 ? numbers[2]! : numbers[1]!;
  if (minutes >= 60 || seconds >= 60) return null;
  return Duration(hours: hours, minutes: minutes, seconds: seconds);
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart' as forui;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';

import '../../../models/download_models.dart';

class InspectorPanel extends StatelessWidget {
  const InspectorPanel({
    super.key,
    required this.preset,
    required this.selectedJob,
    required this.outputDirectory,
    required this.onFormatSelected,
    required this.onRetry,
    required this.onReveal,
    required this.onOpenFullDiskAccessSettings,
  });

  final PresetDefinition preset;
  final DownloadJob? selectedJob;
  final String? outputDirectory;
  final void Function(DownloadJob job, String? formatId) onFormatSelected;
  final ValueChanged<DownloadJob> onRetry;
  final ValueChanged<DownloadJob> onReveal;
  final VoidCallback onOpenFullDiskAccessSettings;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final mediaInfo = selectedJob?.mediaInfo;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inspector', style: theme.textTheme.h4),
          const SizedBox(height: 14),
          _InspectorCard(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mediaInfo == null ? 'Selected Preset' : 'Analyzed Media',
                  style: theme.textTheme.large,
                ),
                const SizedBox(height: 6),
                Text(
                  mediaInfo?.title ?? preset.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.muted,
                ),
                if (mediaInfo != null) ...[
                  const SizedBox(height: 14),
                  _Fact(label: 'Source', value: mediaInfo.sourceLabel),
                  _Fact(
                    label: 'Uploader',
                    value: mediaInfo.uploader ?? 'Unknown',
                  ),
                  _Fact(
                    label: mediaInfo.isPlaylist ? 'Items' : 'Duration',
                    value: mediaInfo.isPlaylist
                        ? '${mediaInfo.playlistCount}'
                        : mediaInfo.durationLabel,
                  ),
                  _Fact(label: 'Formats', value: '${mediaInfo.formatCount}'),
                  if (mediaInfo.formats.isNotEmpty && selectedJob != null) ...[
                    const SizedBox(height: 8),
                    _FormatPicker(
                      job: selectedJob!,
                      formats: mediaInfo.formats,
                      onChanged: (formatId) =>
                          onFormatSelected(selectedJob!, formatId),
                    ),
                  ],
                  _Fact(
                    label: selectedJob?.downloadedFilePath == null
                        ? 'Output'
                        : 'File',
                    value:
                        selectedJob?.downloadedFilePath ??
                        selectedJob?.outputPath ??
                        outputDirectory ??
                        'Not set',
                  ),
                  if (selectedJob?.error != null) ...[
                    const SizedBox(height: 4),
                    _Fact(label: 'Error', value: selectedJob!.error!),
                  ],
                ],
              ],
            ),
          ),
          if (selectedJob != null) ...[
            const SizedBox(height: 14),
            _JobDetailsCard(
              job: selectedJob!,
              outputDirectory: outputDirectory,
              onRetry: onRetry,
              onReveal: onReveal,
              onOpenFullDiskAccessSettings: onOpenFullDiskAccessSettings,
            ),
          ],
        ],
      ),
    );
  }
}

class _InspectorCard extends StatelessWidget {
  const _InspectorCard({
    required this.child,
    this.width,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: Color.lerp(theme.colorScheme.background, Colors.black, 0.035),
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.maxLines = 2});

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyableFact extends StatelessWidget {
  const _CopyableFact({
    required this.label,
    required this.value,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.muted,
            ),
          ),
          const SizedBox(width: 6),
          forui.FTooltip(
            style: const forui.FTooltipStyleDelta.delta(
              hoverEnterDuration: Duration(seconds: 1),
            ),
            tipBuilder: (context, _) => const Text('Copy URL'),
            child: forui.FButton.icon(
              variant: forui.FButtonVariant.ghost,
              size: forui.FButtonSizeVariant.xs,
              semanticsLabel: 'Copy URL',
              onPress: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!context.mounted) return;
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(const SnackBar(content: Text('URL copied')));
              },
              child: const Icon(LucideIcons.copy, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobDetailsCard extends StatelessWidget {
  const _JobDetailsCard({
    required this.job,
    required this.outputDirectory,
    required this.onRetry,
    required this.onReveal,
    required this.onOpenFullDiskAccessSettings,
  });

  final DownloadJob job;
  final String? outputDirectory;
  final ValueChanged<DownloadJob> onRetry;
  final ValueChanged<DownloadJob> onReveal;
  final VoidCallback onOpenFullDiskAccessSettings;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final outputPath =
        job.downloadedFilePath ??
        job.outputPath ??
        outputDirectory ??
        'Not set';
    final progress = job.progress.clamp(0, 1).toDouble();

    return _InspectorCard(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Job Details', style: theme.textTheme.large),
              ),
              if (job.status == DownloadStatus.failed ||
                  job.status == DownloadStatus.stopped) ...[
                forui.FButton(
                  variant: forui.FButtonVariant.outline,
                  size: forui.FButtonSizeVariant.sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => onRetry(job),
                  prefix: const Icon(LucideIcons.rotateCcw, size: 15),
                  child: Text(
                    job.status == DownloadStatus.stopped ? 'Continue' : 'Retry',
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _StatusPill(status: job.status),
            ],
          ),
          const SizedBox(height: 14),
          _ProgressLine(progress: progress, label: job.eta),
          const SizedBox(height: 14),
          _Fact(label: 'Preset', value: job.preset.label),
          if (job.children.isNotEmpty) ...[
            _Fact(label: _childSummaryLabel(job), value: _childSummary(job)),
            if (job.splitEditorSourcePath != null)
              _Fact(
                label: 'Source',
                value: job.splitEditorSourcePath!,
                maxLines: 3,
              ),
          ],
          if (job.startedAt != null)
            _Fact(label: 'Started', value: _formatDateTime(job.startedAt!)),
          if (job.completedAt != null)
            _Fact(label: 'Finished', value: _formatDateTime(job.completedAt!)),
          if (_elapsedLabel(job) case final elapsed?)
            _Fact(label: 'Duration', value: elapsed),
          if (job.downloadedFileSize != null)
            _Fact(label: 'Size', value: _formatBytes(job.downloadedFileSize!)),
          _CopyableFact(label: 'URL', value: job.url, maxLines: 3),
          _Fact(
            label: job.downloadedFilePath == null ? 'Output' : 'File',
            value: outputPath,
            maxLines: 3,
          ),
          if (job.status == DownloadStatus.complete &&
              job.bestOutputPath != null) ...[
            const SizedBox(height: 6),
            _FileActions(job: job, onReveal: onReveal),
          ],
          if (job.error != null) ...[
            const SizedBox(height: 6),
            _ErrorBox(
              message: job.error!,
              onOpenFullDiskAccessSettings: _isFullDiskAccessError(job.error!)
                  ? onOpenFullDiskAccessSettings
                  : null,
            ),
          ],
          if (job.logLines.isNotEmpty) ...[
            const SizedBox(height: 14),
            _JobLog(lines: job.logLines),
          ],
        ],
      ),
    );
  }
}

class _FileActions extends StatelessWidget {
  const _FileActions({required this.job, required this.onReveal});

  final DownloadJob job;
  final ValueChanged<DownloadJob> onReveal;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        forui.FButton(
          variant: forui.FButtonVariant.outline,
          size: forui.FButtonSizeVariant.sm,
          mainAxisSize: MainAxisSize.min,
          onPress: () => onReveal(job),
          prefix: const Icon(LucideIcons.folderOpen, size: 15),
          child: const Text('Show in Folder'),
        ),
      ],
    );
  }
}

class _JobLog extends StatefulWidget {
  const _JobLog({required this.lines});

  final List<String> lines;

  @override
  State<_JobLog> createState() => _JobLogState();
}

class _JobLogState extends State<_JobLog> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(covariant _JobLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lines.length != widget.lines.length ||
        (oldWidget.lines.isNotEmpty &&
            widget.lines.isNotEmpty &&
            oldWidget.lines.last != widget.lines.last)) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Log',
          style: theme.textTheme.small.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.muted,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SingleChildScrollView(
            controller: _controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in widget.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      style: theme.textTheme.small.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.progress, required this.label});

  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final percent = (progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$percent%', style: theme.textTheme.small),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AnimatedProgress(value: progress),
      ],
    );
  }
}

class _AnimatedProgress extends StatelessWidget {
  const _AnimatedProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final clampedValue = value.clamp(0, 1).toDouble();

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: clampedValue),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: theme.colorScheme.muted),
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: animatedValue,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final DownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final color = switch (status) {
      DownloadStatus.ready => const Color(0xFF15803D),
      DownloadStatus.queued => const Color(0xFF0369A1),
      DownloadStatus.analyzing => const Color(0xFFB45309),
      DownloadStatus.downloading => const Color(0xFF4338CA),
      DownloadStatus.stopped => const Color(0xFFB45309),
      DownloadStatus.failed => const Color(0xFFB91C1C),
      DownloadStatus.complete => const Color(0xFF15803D),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.small.copyWith(color: color),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, this.onOpenFullDiskAccessSettings});

  final String message;
  final VoidCallback? onOpenFullDiskAccessSettings;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFB91C1C).withValues(alpha: 0.08),
        border: Border.all(
          color: const Color(0xFFB91C1C).withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.small.copyWith(
              color: const Color(0xFFB91C1C),
            ),
          ),
          if (onOpenFullDiskAccessSettings != null) ...[
            const SizedBox(height: 10),
            forui.FButton.raw(
              variant: forui.FButtonVariant.outline,
              size: forui.FButtonSizeVariant.sm,
              onPress: onOpenFullDiskAccessSettings,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.settings, size: 15),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Open Full Disk Access',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FormatPicker extends StatelessWidget {
  const _FormatPicker({
    required this.job,
    required this.formats,
    required this.onChanged,
  });

  final DownloadJob job;
  final List<MediaFormat> formats;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final selectedFormat =
        formats.any((format) => format.id == job.selectedFormatId)
        ? job.selectedFormatId
        : null;
    final groupedFormats = _groupedFormats(formats);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Quality',
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${formats.length} choices found',
              style: theme.textTheme.muted,
            ),
          ],
        ),
        const SizedBox(height: 6),
        forui.FSelect<String>.rich(
          hint: 'Automatic best match',
          format: (value) {
            if (value.isEmpty) return 'Automatic best match';
            final format = formats.firstWhere(
              (candidate) => candidate.id == value,
              orElse: () => MediaFormat(id: value, label: value),
            );
            return format.displayLabel;
          },
          control: forui.FSelectControl.lifted(
            value: selectedFormat ?? '',
            onChange: (value) => onChanged(
              value == null || value.isEmpty || value.startsWith('__header_')
                  ? null
                  : value,
            ),
          ),
          children: [
            const forui.FSelectItem<String>(
              value: '',
              title: Text('Automatic best match'),
            ),
            for (final entry in groupedFormats.entries) ...[
              forui.FSelectItem<String>(
                value: '__header_${entry.key.name}',
                enabled: false,
                title: Text('${entry.key.label} (${entry.value.length})'),
              ),
              for (final format in entry.value)
                forui.FSelectItem<String>(
                  value: format.id,
                  title: Text(format.displayLabel),
                ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          selectedFormat == null
              ? 'Fetchdeck will use the selected preset to pick the best available format.'
              : 'This job will use the chosen source format instead of the preset default.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Map<FormatGroup, List<MediaFormat>> _groupedFormats(
    List<MediaFormat> formats,
  ) {
    final groups = <FormatGroup, List<MediaFormat>>{};
    for (final group in FormatGroup.values) {
      final groupFormats = formats
          .where((format) => format.group == group)
          .toList(growable: false);
      if (groupFormats.isNotEmpty) {
        groups[group] = groupFormats;
      }
    }
    return groups;
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final month = _monthLabels[local.month - 1];
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month $day, $hour:$minute';
}

String? _elapsedLabel(DownloadJob job) {
  final startedAt = job.startedAt;
  final completedAt = job.completedAt;
  if (startedAt == null || completedAt == null) return null;

  final elapsed = completedAt.difference(startedAt);
  if (elapsed.isNegative) return null;
  return _formatDuration(elapsed);
}

String _childSummaryLabel(DownloadJob job) {
  final firstKind = job.children.first.kind;
  return switch (firstKind) {
    DownloadItemKind.manualSegment => 'Segments',
    DownloadItemKind.chapter => 'Chapters',
    DownloadItemKind.playlistEntry => 'Items',
  };
}

String _childSummary(DownloadJob job) {
  final children = job.children;
  final selected = children.where((child) => child.isSelected).length;
  final active = children
      .where(
        (child) =>
            child.status == DownloadStatus.queued ||
            child.status == DownloadStatus.downloading,
      )
      .length;
  final complete = children
      .where((child) => child.status == DownloadStatus.complete)
      .length;
  final failed = children
      .where((child) => child.status == DownloadStatus.failed)
      .length;
  final parts = <String>[
    '$selected selected',
    if (active > 0) '$active active',
    '$complete complete',
    if (failed > 0) '$failed failed',
  ];
  return parts.join(' • ');
}

String _formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds}s';

  final minutes = duration.inMinutes;
  final remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return remainingSeconds == 0
        ? '${minutes}m'
        : '${minutes}m ${remainingSeconds}s';
  }

  final hours = duration.inHours;
  final remainingMinutes = minutes % 60;
  return remainingMinutes == 0 ? '${hours}h' : '${hours}h ${remainingMinutes}m';
}

const _monthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  if (unitIndex == 0) return '$bytes B';
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}';
}

bool _isFullDiskAccessError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('full disk access') ||
      (lower.contains('safari') &&
          lower.contains('cookies') &&
          lower.contains('operation not permitted'));
}

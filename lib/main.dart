import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'models/download_models.dart';
import 'services/tools/tool_discovery.dart';
import 'services/yt_dlp/yt_dlp_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1180, 760),
        minimumSize: Size(960, 640),
        center: true,
        title: 'Fetchdeck',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  runApp(const FetchdeckApp());
}

class FetchdeckApp extends StatelessWidget {
  const FetchdeckApp({super.key, this.enableToolInspection = true});

  final bool enableToolInspection;

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      debugShowCheckedModeBanner: false,
      title: 'Fetchdeck',
      themeMode: ThemeMode.system,
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: const ShadZincColorScheme.light(),
        radius: BorderRadius.circular(8),
      ),
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: const ShadZincColorScheme.dark(),
        radius: BorderRadius.circular(8),
      ),
      home: DownloadWorkbench(enableToolInspection: enableToolInspection),
    );
  }
}

class DownloadWorkbench extends StatefulWidget {
  const DownloadWorkbench({super.key, this.enableToolInspection = true});

  final bool enableToolInspection;

  @override
  State<DownloadWorkbench> createState() => _DownloadWorkbenchState();
}

class _DownloadWorkbenchState extends State<DownloadWorkbench> {
  final urlController = TextEditingController();
  final toolDiscovery = ToolDiscovery();

  var selectedPreset = DownloadPreset.mp3_320;
  var selectedSection = 'Downloads';
  var toolSet = const ToolSet.empty();
  var isInspectingTools = true;
  var isAnalyzing = false;
  var statusMessage = 'Checking yt-dlp, ffmpeg, and ffprobe...';
  String? selectedJobId;

  final jobs = <DownloadJob>[];

  DownloadJob? get selectedJob {
    for (final job in jobs) {
      if (job.id == selectedJobId) return job;
    }
    return jobs.isEmpty ? null : jobs.first;
  }

  @override
  void initState() {
    super.initState();
    if (widget.enableToolInspection) {
      _inspectTools();
    } else {
      isInspectingTools = false;
      statusMessage = 'Tool inspection skipped for tests.';
    }
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Row(
          children: [
            _Sidebar(
              selected: selectedSection,
              toolSet: toolSet,
              isInspectingTools: isInspectingTools,
              onSelected: (value) => setState(() => selectedSection = value),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _Toolbar(
                    controller: urlController,
                    selectedPreset: selectedPreset,
                    isAnalyzing: isAnalyzing,
                    canAnalyze: toolSet.ytDlp.isAvailable && !isInspectingTools,
                    onPresetChanged: (preset) {
                      setState(() => selectedPreset = preset);
                    },
                    onAdd: _analyzeUrl,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _QueuePanel(
                              jobs: jobs,
                              selectedJobId: selectedJobId,
                              onSelected: (job) {
                                setState(() => selectedJobId = job.id);
                              },
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 4,
                            child: _InspectorPanel(
                              preset: selectedPreset,
                              selectedJob: selectedJob,
                              toolSet: toolSet,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _StatusBar(message: statusMessage),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _inspectTools() async {
    setState(() {
      isInspectingTools = true;
      statusMessage = 'Checking local tools...';
    });

    final inspectedTools = await toolDiscovery.inspect();
    if (!mounted) return;

    setState(() {
      toolSet = inspectedTools;
      isInspectingTools = false;
      statusMessage = inspectedTools.ytDlp.isAvailable
          ? 'Ready. yt-dlp found at ${inspectedTools.ytDlp.path}.'
          : 'yt-dlp was not found. Install it or place yt-dlp/yt-dlp_macos in Downloads, ~/.local/bin, /opt/homebrew/bin, or /usr/local/bin.';
    });
  }

  Future<void> _analyzeUrl() async {
    final rawUrl = urlController.text.trim();
    if (rawUrl.isEmpty || isAnalyzing) return;

    final executable = toolSet.ytDlp.path;
    if (executable == null) {
      setState(() {
        statusMessage = 'Cannot analyze yet because yt-dlp was not found.';
      });
      return;
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final pendingJob = DownloadJob(
      id: id,
      url: rawUrl,
      title: 'Analyzing URL',
      source: rawUrl,
      preset: selectedPreset,
      status: DownloadStatus.analyzing,
      progress: 0.08,
      eta: 'Reading metadata',
    );

    setState(() {
      isAnalyzing = true;
      selectedJobId = id;
      jobs.insert(0, pendingJob);
      urlController.clear();
      statusMessage = 'Running yt-dlp metadata analysis...';
    });

    try {
      final mediaInfo = await YtDlpService(
        executable: executable,
      ).getMetadata(rawUrl);
      if (!mounted) return;
      _replaceJob(
        id,
        pendingJob.copyWith(
          title: mediaInfo.title,
          source: mediaInfo.sourceLabel,
          status: DownloadStatus.ready,
          progress: 0,
          eta: mediaInfo.isPlaylist
              ? '${mediaInfo.playlistCount} items'
              : mediaInfo.durationLabel,
          mediaInfo: mediaInfo,
        ),
      );
      setState(() {
        statusMessage = mediaInfo.isPlaylist
            ? 'Analyzed playlist: ${mediaInfo.title}.'
            : 'Analyzed video: ${mediaInfo.title}.';
      });
    } on YtDlpException catch (error) {
      if (!mounted) return;
      _replaceJob(
        id,
        pendingJob.copyWith(
          title: 'Analysis failed',
          status: DownloadStatus.failed,
          progress: 0,
          eta: 'Failed',
          error: error.message,
        ),
      );
      setState(() => statusMessage = error.message);
    } catch (error) {
      if (!mounted) return;
      _replaceJob(
        id,
        pendingJob.copyWith(
          title: 'Analysis failed',
          status: DownloadStatus.failed,
          progress: 0,
          eta: 'Failed',
          error: error.toString(),
        ),
      );
      setState(() => statusMessage = 'Unexpected analysis error: $error');
    } finally {
      if (mounted) {
        setState(() => isAnalyzing = false);
      }
    }
  }

  void _replaceJob(String id, DownloadJob replacement) {
    setState(() {
      final index = jobs.indexWhere((job) => job.id == id);
      if (index == -1) return;
      jobs[index] = replacement;
    });
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.toolSet,
    required this.isInspectingTools,
    required this.onSelected,
  });

  final String selected;
  final ToolSet toolSet;
  final bool isInspectingTools;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final items = <({IconData icon, String label})>[
      (icon: LucideIcons.download, label: 'Downloads'),
      (icon: LucideIcons.listPlus, label: 'Queue'),
      (icon: LucideIcons.library, label: 'Library'),
      (icon: LucideIcons.slidersHorizontal, label: 'Presets'),
      (icon: LucideIcons.settings, label: 'Settings'),
    ];

    return Container(
      width: 220,
      color: theme.colorScheme.muted.withValues(alpha: 0.38),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.audioLines,
                  color: theme.colorScheme.primaryForeground,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fetchdeck',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.large,
                    ),
                    Text(
                      'yt-dlp desktop',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _NavButton(
                icon: item.icon,
                label: item.label,
                selected: selected == item.label,
                onPressed: () => onSelected(item.label),
              ),
            ),
          const Spacer(),
          _ToolHealthChip(
            icon: LucideIcons.circleCheck,
            label: 'Flutter 3.44.1',
            healthy: true,
          ),
          const SizedBox(height: 8),
          _ToolHealthChip(
            icon: isInspectingTools
                ? LucideIcons.loaderCircle
                : toolSet.ytDlp.isAvailable
                ? LucideIcons.circleCheck
                : LucideIcons.circleAlert,
            label: isInspectingTools
                ? 'yt-dlp checking'
                : toolSet.ytDlp.shortLabel('yt-dlp'),
            healthy: toolSet.ytDlp.isAvailable,
          ),
          const SizedBox(height: 8),
          _ToolHealthChip(
            icon: toolSet.ffmpeg.isAvailable
                ? LucideIcons.circleCheck
                : LucideIcons.circleAlert,
            label: toolSet.ffmpeg.shortLabel('ffmpeg'),
            healthy: toolSet.ffmpeg.isAvailable,
          ),
          const SizedBox(height: 8),
          _ToolHealthChip(
            icon: toolSet.ffprobe.isAvailable
                ? LucideIcons.circleCheck
                : LucideIcons.circleAlert,
            label: toolSet.ffprobe.shortLabel('ffprobe'),
            healthy: toolSet.ffprobe.isAvailable,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ShadButton.ghost(
      width: double.infinity,
      onPressed: onPressed,
      backgroundColor: selected ? theme.colorScheme.accent : null,
      child: Row(
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

class _ToolHealthChip extends StatelessWidget {
  const _ToolHealthChip({
    required this.icon,
    required this.label,
    required this.healthy,
  });

  final IconData icon;
  final String label;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: healthy
                ? const Color(0xFF15803D)
                : theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.small,
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.selectedPreset,
    required this.isAnalyzing,
    required this.canAnalyze,
    required this.onPresetChanged,
    required this.onAdd,
  });

  final TextEditingController controller;
  final DownloadPreset selectedPreset;
  final bool isAnalyzing;
  final bool canAnalyze;
  final ValueChanged<DownloadPreset> onPresetChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: controller,
              placeholder: const Text(
                'Paste a video, playlist, channel, or batch URL',
              ),
              leading: const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Icon(LucideIcons.link, size: 16),
              ),
              onSubmitted: (_) => onAdd(),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: ShadSelect<DownloadPreset>(
              placeholder: const Text('Preset'),
              initialValue: selectedPreset,
              options: [
                for (final preset in DownloadPreset.values)
                  ShadOption(value: preset, child: Text(preset.label)),
              ],
              selectedOptionBuilder: (context, value) => Text(value.label),
              onChanged: (value) {
                if (value != null) onPresetChanged(value);
              },
            ),
          ),
          const SizedBox(width: 12),
          ShadButton(
            onPressed: canAnalyze && !isAnalyzing ? onAdd : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAnalyzing ? LucideIcons.loaderCircle : LucideIcons.plus,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(isAnalyzing ? 'Analyzing' : 'Add'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            onPressed: () {},
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.folderOpen,
                  size: 16,
                  color: theme.colorScheme.foreground,
                ),
                const SizedBox(width: 8),
                const Text('Output'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.jobs,
    required this.selectedJobId,
    required this.onSelected,
  });

  final List<DownloadJob> jobs;
  final String? selectedJobId;
  final ValueChanged<DownloadJob> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180),
              child: Text('Download Queue', style: theme.textTheme.h4),
            ),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () {},
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.play, size: 15),
                  SizedBox(width: 6),
                  Text('Start All'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: jobs.isEmpty
              ? const _EmptyQueue()
              : ListView.separated(
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return _JobRow(
                      job: job,
                      selected: selectedJobId == job.id,
                      onPressed: () => onSelected(job),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.clipboardList,
              size: 34,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text('No analyzed URLs yet', style: theme.textTheme.large),
            const SizedBox(height: 6),
            Text(
              'Paste a URL above. Fetchdeck will ask yt-dlp for metadata and add the result here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    required this.job,
    required this.selected,
    required this.onPressed,
  });

  final DownloadJob job;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.accent.withValues(alpha: 0.45)
              : null,
          border: Border.all(
            color: selected ? theme.colorScheme.ring : theme.colorScheme.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _Thumbnail(info: job.mediaInfo),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    '${job.source} • ${job.preset.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.muted,
                  ),
                  if (job.error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      job.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.small.copyWith(
                        color: const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ShadProgress(value: job.progress),
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 118,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusBadge(status: job.status),
                  const SizedBox(height: 8),
                  Text(
                    job.eta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.small,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ShadIconButton.ghost(
              icon: const Icon(LucideIcons.ellipsisVertical, size: 17),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.info});

  final MediaInfo? info;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final thumbnail = info?.thumbnail;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 72,
        height: 48,
        color: theme.colorScheme.muted,
        child: thumbnail == null
            ? Icon(
                info?.isPlaylist == true
                    ? LucideIcons.listVideo
                    : LucideIcons.video,
                color: theme.colorScheme.mutedForeground,
              )
            : Image.network(
                thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  LucideIcons.video,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = switch (status) {
      DownloadStatus.ready => const Color(0xFF15803D),
      DownloadStatus.queued => const Color(0xFF0369A1),
      DownloadStatus.analyzing => const Color(0xFFB45309),
      DownloadStatus.downloading => const Color(0xFF4338CA),
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

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({
    required this.preset,
    required this.selectedJob,
    required this.toolSet,
  });

  final DownloadPreset preset;
  final DownloadJob? selectedJob;
  final ToolSet toolSet;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mediaInfo = selectedJob?.mediaInfo;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inspector', style: theme.textTheme.h4),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
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
                ],
                const SizedBox(height: 16),
                _CommandPreview(preset: selectedJob?.preset ?? preset),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Engine Status', style: theme.textTheme.large),
                const SizedBox(height: 12),
                _TaskLine(done: true, text: 'Desktop-only Flutter scaffold'),
                _TaskLine(done: true, text: 'shadcn_ui theme shell'),
                _TaskLine(
                  done: toolSet.ytDlp.isAvailable,
                  text: 'yt-dlp process adapter',
                ),
                _TaskLine(
                  done:
                      toolSet.ffmpeg.isAvailable && toolSet.ffprobe.isAvailable,
                  text: 'ffmpeg and tool health checks',
                ),
                _TaskLine(
                  done: selectedJob?.mediaInfo != null,
                  text: 'metadata JSON parser',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 74, child: Text(label, style: theme.textTheme.small)),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandPreview extends StatelessWidget {
  const _CommandPreview({required this.preset});

  final DownloadPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        preset.commandSummary,
        style: theme.textTheme.small.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}

class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.done, required this.text});

  final bool done;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(
            done ? LucideIcons.circleCheck : LucideIcons.circle,
            size: 16,
            color: done
                ? const Color(0xFF15803D)
                : theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: Row(
        children: [
          Icon(
            LucideIcons.terminal,
            size: 15,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

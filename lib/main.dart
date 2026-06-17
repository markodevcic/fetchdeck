import 'dart:async';
import 'dart:io';

import 'package:forui/forui.dart' as forui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'features/downloads/application/analysis_controller.dart';
import 'features/downloads/application/queue_controller.dart';
import 'features/downloads/application/url_input_controller.dart';
import 'features/downloads/presentation/download_toolbar.dart';
import 'features/downloads/presentation/inspector_panel.dart';
import 'features/downloads/presentation/queue_panel.dart';
import 'features/presets/presentation/presets_panel.dart';
import 'features/settings/application/app_settings_controller.dart';
import 'features/settings/application/app_info_controller.dart';
import 'features/settings/application/tool_controller.dart';
import 'features/settings/application/tool_kind.dart';
import 'features/settings/presentation/settings_panel.dart';
import 'features/shell/application/navigation_controller.dart';
import 'features/shell/application/status_controller.dart';
import 'features/shell/application/workbench_actions.dart';
import 'features/shell/presentation/app_sidebar.dart';
import 'features/shell/presentation/status_bar.dart';
import 'features/split_editor/application/split_audio_controller.dart';
import 'features/split_editor/application/split_editor_controller.dart';
import 'features/split_editor/presentation/split_editor_drawer.dart';
import 'models/download_models.dart';
import 'services/clipboard/clipboard_url_service.dart';
import 'services/files/file_selection_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1180, 760),
        minimumSize: Size(1160, 640),
        center: true,
        title: 'Fetchdeck',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  runApp(const ProviderScope(child: FetchdeckApp()));
}

class FetchdeckApp extends StatelessWidget {
  const FetchdeckApp({super.key, this.enableToolInspection = true});

  final bool enableToolInspection;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fetchdeck',
      themeMode: ThemeMode.system,
      theme: fetchdeckMaterialTheme(Brightness.light),
      darkTheme: fetchdeckMaterialTheme(Brightness.dark),
      home: Builder(
        builder: (context) {
          final brightness = MediaQuery.platformBrightnessOf(context);
          final foruiTheme = brightness == Brightness.dark
              ? forui.FThemes.zinc.dark.desktop
              : forui.FThemes.zinc.light.desktop;

          return forui.FTheme(
            data: foruiTheme,
            child: DownloadWorkbench(
              enableToolInspection: enableToolInspection,
            ),
          );
        },
      ),
    );
  }
}

class DownloadWorkbench extends ConsumerStatefulWidget {
  const DownloadWorkbench({super.key, this.enableToolInspection = true});

  final bool enableToolInspection;

  @override
  ConsumerState<DownloadWorkbench> createState() => _DownloadWorkbenchState();
}

class _DownloadWorkbenchState extends ConsumerState<DownloadWorkbench>
    with WidgetsBindingObserver {
  final urlController = TextEditingController();

  Timer? pasteAnalyzeDebounce;
  late final SplitAudioController splitAudioController;

  String? get outputDirectory {
    return ref.read(appSettingsControllerProvider).outputDirectory;
  }

  String get selectedSection => ref.read(navigationControllerProvider);

  WorkbenchActions get actions => ref.read(workbenchActionsProvider);

  bool get isSettingsView => selectedSection == 'Settings';

  bool get isPresetsView => selectedSection == 'Presets';

  @override
  void initState() {
    super.initState();
    splitAudioController = ref.read(splitAudioControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    urlController.addListener(_handleUrlInputChanged);
    if (widget.enableToolInspection) {
      Future<void>.microtask(actions.bootstrap);
    } else {
      Future<void>.microtask(
        () => _setStatusMessage('Tool inspection skipped for tests.'),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseSplitAudio();
    pasteAnalyzeDebounce?.cancel();
    urlController.removeListener(_handleUrlInputChanged);
    urlController.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    _releaseSplitAudio();
    super.reassemble();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _releaseSplitAudio();
    } else if (state == AppLifecycleState.resumed) {
      actions.reconcileQueueFromDisk();
    }
  }

  void _releaseSplitAudio() {
    unawaited(splitAudioController.release());
  }

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final selectedSection = ref.watch(navigationControllerProvider);
    final statusMessage = ref.watch(statusControllerProvider);
    final activities = ref.watch(activityControllerProvider).entries;
    final queueState = ref.watch(queueControllerProvider);
    final analysisState = ref.watch(analysisControllerProvider);
    final settingsState = ref.watch(appSettingsControllerProvider);
    final appInfo = ref.watch(appInfoProvider);
    final toolState = ref.watch(toolControllerProvider);
    final toolSet = toolState.toolSet;
    final availablePresets = settingsState.availablePresets;
    final selectedPreset = settingsState.activePreset;
    final outputDirectory = settingsState.outputDirectory;
    final visibleJobs = queueState.visibleJobs();
    final selectedJob = queueState.selectedJob();
    final canStartVisibleJobs = queueState.canStartVisibleJobs();

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      AppSidebar(
                        selected: selectedSection,
                        onSelected: _selectSection,
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          children: [
                            DownloadToolbar(
                              controller: urlController,
                              presets: availablePresets,
                              selectedPreset: selectedPreset,
                              isAnalyzing: analysisState.isAnalyzing,
                              onPresetChanged: (preset) {
                                _setSelectedPreset(preset);
                              },
                              onAdd: _analyzeUrl,
                              onPaste: _pasteFromClipboard,
                              outputDirectory: outputDirectory,
                              onPickOutput: _pickOutputDirectory,
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: isSettingsView
                                    ? SettingsPanel(
                                        toolSet: toolSet,
                                        appVersion: appInfo.when(
                                          data: (info) => info.displayVersion,
                                          loading: () => 'Loading...',
                                          error: (_, _) => 'Unknown',
                                        ),
                                        ytDlpPath: toolState.visiblePath(
                                          ToolKind.ytDlp,
                                        ),
                                        ffmpegPath: toolState.visiblePath(
                                          ToolKind.ffmpeg,
                                        ),
                                        ffprobePath: toolState.visiblePath(
                                          ToolKind.ffprobe,
                                        ),
                                        isChecking: toolState.isInspecting,
                                        updateInfo: toolState.updateInfo,
                                        concurrencyLimit:
                                            settingsState.concurrencyLimit,
                                        authentication:
                                            settingsState.authentication,
                                        isCheckingUpdate:
                                            toolState.isCheckingYtDlpUpdate,
                                        isUpdatingYtDlp:
                                            toolState.isUpdatingYtDlp,
                                        updateDismissed:
                                            toolState.updateDismissed,
                                        onPickYtDlp: () =>
                                            _pickToolPath(ToolKind.ytDlp),
                                        onPickFfmpeg: () =>
                                            _pickToolPath(ToolKind.ffmpeg),
                                        onPickFfprobe: () =>
                                            _pickToolPath(ToolKind.ffprobe),
                                        onClearYtDlp: () =>
                                            _clearToolPath(ToolKind.ytDlp),
                                        onClearFfmpeg: () =>
                                            _clearToolPath(ToolKind.ffmpeg),
                                        onClearFfprobe: () =>
                                            _clearToolPath(ToolKind.ffprobe),
                                        onRecheck: _recheckTools,
                                        onCheckYtDlpUpdate: _checkYtDlpUpdate,
                                        onInstallYtDlpUpdate:
                                            _installYtDlpUpdate,
                                        onSkipYtDlpUpdate: _skipYtDlpUpdate,
                                        onConcurrencyChanged:
                                            actions.setConcurrencyLimit,
                                        onAuthenticationChanged:
                                            actions.setAuthentication,
                                      )
                                    : isPresetsView
                                    ? PresetsPanel(
                                        presets: availablePresets,
                                        selectedPreset: selectedPreset,
                                        onSelected: _setSelectedPreset,
                                        onCreate: _createCustomPreset,
                                        onDelete: _deleteCustomPreset,
                                      )
                                    : Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 7,
                                            child: QueuePanel(
                                              title: 'Downloads',
                                              jobs: visibleJobs,
                                              selectedJobId:
                                                  queueState.selectedJobId,
                                              hasOutputDirectory:
                                                  outputDirectory != null,
                                              canStartAll: canStartVisibleJobs,
                                              statusFilter:
                                                  queueState.statusFilter,
                                              searchQuery:
                                                  queueState.searchQuery,
                                              onSelected: (job) {
                                                ref
                                                    .read(
                                                      queueControllerProvider
                                                          .notifier,
                                                    )
                                                    .selectJob(job.id);
                                              },
                                              onStart: _startOrRetryDownload,
                                              onCancel: _cancelDownload,
                                              onSplit: (job) {
                                                unawaited(
                                                  _openSplitEditor(job),
                                                );
                                              },
                                              onReveal: _revealOutput,
                                              onRemove: _removeJob,
                                              onStartAll: _startAllDownloads,
                                              onStatusFilterChanged: (filter) {
                                                ref
                                                    .read(
                                                      queueControllerProvider
                                                          .notifier,
                                                    )
                                                    .setStatusFilter(filter);
                                              },
                                              onSearchChanged: (query) {
                                                ref
                                                    .read(
                                                      queueControllerProvider
                                                          .notifier,
                                                    )
                                                    .setSearchQuery(query);
                                              },
                                              onToggleExpanded: (job) {
                                                ref
                                                    .read(
                                                      queueControllerProvider
                                                          .notifier,
                                                    )
                                                    .toggleExpanded(job.id);
                                              },
                                              onChildSelected:
                                                  ({
                                                    required child,
                                                    required isSelected,
                                                    required job,
                                                  }) {
                                                    ref
                                                        .read(
                                                          queueControllerProvider
                                                              .notifier,
                                                        )
                                                        .setChildSelected(
                                                          jobId: job.id,
                                                          childId: child.id,
                                                          isSelected:
                                                              isSelected,
                                                        );
                                                  },
                                              onSelectAllChildren:
                                                  ({
                                                    required isSelected,
                                                    required job,
                                                  }) {
                                                    ref
                                                        .read(
                                                          queueControllerProvider
                                                              .notifier,
                                                        )
                                                        .setAllChildrenSelected(
                                                          job.id,
                                                          isSelected,
                                                        );
                                                  },
                                            ),
                                          ),
                                          const SizedBox(width: 20),
                                          Expanded(
                                            flex: 4,
                                            child: InspectorPanel(
                                              preset: selectedPreset,
                                              selectedJob: selectedJob,
                                              outputDirectory: outputDirectory,
                                              onFormatSelected: _setJobFormat,
                                              onRetry: _retryJob,
                                              onReveal: _revealOutput,
                                              onOpenFullDiskAccessSettings:
                                                  _openFullDiskAccessSettings,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                StatusBar(message: statusMessage, activities: activities),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectSection(String section) {
    actions.selectSection(section);
  }

  Future<void> _pickOutputDirectory() async {
    final selectedDirectory = await ref
        .read(fileSelectionServiceProvider)
        .pickOutputDirectory(initialDirectory: outputDirectory);
    if (selectedDirectory == null || !mounted) return;

    await actions.setOutputDirectory(selectedDirectory);
  }

  Future<void> _setSelectedPreset(PresetDefinition preset) async {
    await actions.setSelectedPreset(preset);
  }

  Future<bool?> _showConfirmationDialog({
    required String title,
    required String description,
    required String confirmLabel,
    required IconData confirmIcon,
    bool destructive = false,
  }) {
    return forui.showFDialog<bool>(
      context: context,
      builder: (context, style, animation) {
        return forui.FDialog.adaptive(
          animation: animation,
          title: Text(title),
          body: Text(description),
          actions: [
            forui.FButton(
              variant: destructive
                  ? forui.FButtonVariant.destructive
                  : forui.FButtonVariant.primary,
              onPress: () => Navigator.of(context).pop(true),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(confirmIcon, size: 15),
                  const SizedBox(width: 6),
                  Text(confirmLabel),
                ],
              ),
            ),
            forui.FButton(
              variant: forui.FButtonVariant.outline,
              onPress: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createCustomPreset() async {
    final preset = await forui.showFDialog<PresetDefinition>(
      context: context,
      builder: (context, style, animation) =>
          PresetEditorDialog(key: const Key('preset-editor-dialog')),
    );
    if (preset == null || !mounted) return;

    await actions.createCustomPreset(preset);
  }

  Future<void> _deleteCustomPreset(PresetDefinition preset) async {
    final confirmed = await _showConfirmationDialog(
      title: 'Delete this preset?',
      description:
          'This removes "${preset.label}" from Fetchdeck. Built-in presets stay available.',
      confirmLabel: 'Delete',
      confirmIcon: LucideIcons.trash2,
      destructive: true,
    );
    if (!mounted || confirmed != true) return;

    await actions.deleteCustomPreset(preset);
  }

  Future<void> _recheckTools() async {
    await actions.recheckTools();
  }

  Future<void> _checkYtDlpUpdate({bool automatic = false}) async {
    await actions.checkYtDlpUpdate(automatic: automatic);
  }

  Future<void> _installYtDlpUpdate() async {
    await actions.installYtDlpUpdate();
  }

  void _skipYtDlpUpdate() {
    actions.skipYtDlpUpdate();
  }

  Future<void> _pickToolPath(ToolKind tool) async {
    final currentPath = ref.read(toolControllerProvider).visiblePath(tool);
    final path = await ref
        .read(fileSelectionServiceProvider)
        .pickToolPath(toolLabel: tool.label, currentPath: currentPath);
    if (path == null || !mounted) return;

    await actions.setToolPath(tool: tool, path: path);
  }

  Future<void> _clearToolPath(ToolKind tool) async {
    await actions.clearToolPath(tool);
  }

  Future<void> _analyzeUrl() async {
    var rawUrl = urlController.text.trim();
    pasteAnalyzeDebounce?.cancel();
    if (rawUrl.isEmpty) {
      rawUrl = await ref.read(clipboardUrlServiceProvider).readUrl();
      if (rawUrl.isNotEmpty) {
        urlController.text = rawUrl;
        ref
            .read(urlInputControllerProvider.notifier)
            .setProgrammaticText(rawUrl);
      } else {
        _setStatusMessage(
          'Paste a URL into the field, or copy one and press Add again.',
        );
        return;
      }
    }
    final didAnalyze = await actions.analyzeUrl(rawUrl);
    if (!mounted) return;
    if (didAnalyze) {
      setState(() {
        urlController.clear();
        ref.read(urlInputControllerProvider.notifier).clear();
      });
    }
  }

  void _handleUrlInputChanged() {
    final current = urlController.text.trim();
    final isAnalyzing = ref.read(analysisControllerProvider).isAnalyzing;
    final action = ref
        .read(urlInputControllerProvider.notifier)
        .handleChanged(current, isAnalyzing: isAnalyzing);

    if (action == UrlInputAction.none) {
      pasteAnalyzeDebounce?.cancel();
      return;
    }

    _setStatusMessage('Pasted URL detected. Starting analysis...');
    pasteAnalyzeDebounce?.cancel();
    pasteAnalyzeDebounce = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      if (urlController.text.trim() == current &&
          !ref.read(analysisControllerProvider).isAnalyzing) {
        _analyzeUrl();
      }
    });
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardUrl = await ref.read(clipboardUrlServiceProvider).readUrl();
    if (clipboardUrl.isEmpty) {
      _setStatusMessage('Clipboard does not contain a URL.');
      return;
    }

    pasteAnalyzeDebounce?.cancel();
    urlController.text = clipboardUrl;
    ref
        .read(urlInputControllerProvider.notifier)
        .setProgrammaticText(clipboardUrl);
    _setStatusMessage('Pasted URL from clipboard.');
    await _analyzeUrl();
  }

  Future<void> _startAllDownloads() async {
    await actions.startVisibleDownloads();
  }

  Future<void> _startDownload(DownloadJob job) async {
    await actions.startDownload(job);
  }

  Future<void> _startOrRetryDownload(DownloadJob job) async {
    if (job.status == DownloadStatus.failed) {
      await actions.retryJob(job);
      return;
    }

    final reconciledJob = ref
        .read(queueControllerProvider.notifier)
        .reconcileLocalFilesForJob(job);
    final preparedJob = _hasSelectedManualSegments(reconciledJob)
        ? await _confirmReexportIfNeeded(reconciledJob)
        : await _confirmRedownloadIfNeeded(reconciledJob);
    if (preparedJob == null) return;

    await _startDownload(preparedJob);
  }

  Future<void> _retryJob(DownloadJob job) async {
    await actions.retryJob(job);
  }

  Future<DownloadJob?> _confirmRedownloadIfNeeded(DownloadJob job) async {
    if (job.status == DownloadStatus.stopped) return job;

    final existingTargets = _existingDownloadTargets(job);
    if (existingTargets.isEmpty) return job;

    final confirmed = await _showConfirmationDialog(
      title: _redownloadTitle(existingTargets),
      description: _redownloadDescription(existingTargets),
      confirmLabel: 'Redownload',
      confirmIcon: LucideIcons.download,
    );
    if (!mounted || confirmed != true) return null;

    return _resetExistingDownloadTargets(job, existingTargets);
  }

  Future<DownloadJob?> _confirmReexportIfNeeded(DownloadJob job) async {
    if (job.status == DownloadStatus.stopped) return job;

    final existingTargets = _existingManualSegmentTargets(job);
    if (existingTargets.isEmpty) return job;

    final confirmed = await _showConfirmationDialog(
      title: _reexportTitle(existingTargets),
      description: _reexportDescription(existingTargets),
      confirmLabel: 'Re-export',
      confirmIcon: LucideIcons.fileOutput,
    );
    if (!mounted || confirmed != true) return null;

    return _resetExistingDownloadTargets(job, existingTargets);
  }

  List<_ExistingDownloadTarget> _existingDownloadTargets(DownloadJob job) {
    if (_hasSelectedManualSegments(job)) return const [];

    final selectedChildren = job.children
        .where(
          (child) =>
              child.isSelected &&
              (child.kind == DownloadItemKind.playlistEntry ||
                  child.kind == DownloadItemKind.chapter),
        )
        .toList(growable: false);
    if (selectedChildren.isNotEmpty &&
        selectedChildren.any((child) => !_pathExists(child.bestOutputPath))) {
      return const [];
    }

    final childTargets = [
      for (final child in selectedChildren)
        if (_pathExists(child.bestOutputPath))
          _ExistingDownloadTarget.child(
            id: child.id,
            title: child.title,
            path: child.bestOutputPath!,
          ),
    ];
    if (childTargets.isNotEmpty) return childTargets;

    final jobPath = job.downloadedFilePath;
    if (_pathExists(jobPath)) {
      return [_ExistingDownloadTarget.job(title: job.title, path: jobPath!)];
    }

    final outputPath = job.outputPath;
    if (job.status == DownloadStatus.complete && _pathExists(outputPath)) {
      return [_ExistingDownloadTarget.job(title: job.title, path: outputPath!)];
    }

    return const [];
  }

  List<_ExistingDownloadTarget> _existingManualSegmentTargets(DownloadJob job) {
    return [
      for (final child in job.children)
        if (child.isSelected &&
            child.kind == DownloadItemKind.manualSegment &&
            _pathExists(child.bestOutputPath))
          _ExistingDownloadTarget.child(
            id: child.id,
            title: child.title,
            path: child.bestOutputPath!,
          ),
    ];
  }

  DownloadJob _resetExistingDownloadTargets(
    DownloadJob job,
    List<_ExistingDownloadTarget> targets,
  ) {
    final childIds = targets
        .where((target) => target.isChild)
        .map((target) => target.id)
        .toSet();
    late DownloadJob updatedJob;
    ref.read(queueControllerProvider.notifier).update(job.id, (current) {
      updatedJob = childIds.isEmpty
          ? current.copyWith(
              status: DownloadStatus.ready,
              progress: 0,
              eta: 'Ready to download',
              error: null,
              clearDownloadedFilePath: true,
              clearDownloadedFileSize: true,
              clearCompletedAt: true,
            )
          : current.copyWith(
              status: DownloadStatus.ready,
              progress: 0,
              eta: 'Ready to download',
              error: null,
              clearCompletedAt: true,
              children: [
                for (final child in current.children)
                  childIds.contains(child.id)
                      ? child.copyWith(
                          status: DownloadStatus.ready,
                          progress: 0,
                          clearError: true,
                          clearOutputPath: true,
                          clearDownloadedFilePath: true,
                          clearDownloadedFileSize: true,
                          clearStartedAt: true,
                          clearCompletedAt: true,
                        )
                      : child,
              ],
            );
      return updatedJob;
    });
    return updatedJob;
  }

  void _cancelDownload(DownloadJob job) {
    actions.cancelDownload(job);
  }

  Future<void> _openSplitEditor(DownloadJob job) async {
    final sourcePath = job.splitEditorSourcePath;
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      _setStatusMessage(
        'Download ${job.title} before opening the split editor.',
      );
      return;
    }

    await ref.read(splitEditorControllerProvider.notifier).open(job);
    if (!mounted) return;

    ref.read(queueControllerProvider.notifier).selectJob(job.id);
    _setStatusMessage('Opened split editor for ${job.title}.');

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width,
        maxHeight: MediaQuery.sizeOf(context).height,
      ),
      builder: (sheetContext) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final sheetWidth = (constraints.maxWidth - 48).clamp(720.0, 1040.0);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 640),
                  child: Center(
                    child: SizedBox(
                      width: sheetWidth,
                      child: SplitEditorDrawer(
                        job: job,
                        onClose: () => Navigator.of(sheetContext).pop(),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) {
      ref.read(splitEditorControllerProvider.notifier).close();
      return;
    }
    _closeSplitEditor();
  }

  void _closeSplitEditor() {
    ref.read(splitEditorControllerProvider.notifier).close();
    _setStatusMessage('Split editor closed.');
  }

  Future<void> _revealOutput(DownloadJob job) async {
    await actions.revealOutput(job);
  }

  Future<void> _openFullDiskAccessSettings() async {
    await actions.openFullDiskAccessSettings();
  }

  void _removeJob(DownloadJob job) {
    unawaited(_confirmAndRemoveJob(job));
  }

  Future<void> _confirmAndRemoveJob(DownloadJob job) async {
    final confirmed = await _showConfirmationDialog(
      title: 'Remove this item?',
      description: _removeJobDescription(job),
      confirmLabel: 'Remove',
      confirmIcon: LucideIcons.trash2,
      destructive: true,
    );
    if (!mounted || confirmed != true) return;

    actions.removeJob(job);
  }

  String _removeJobDescription(DownloadJob job) {
    if (job.status == DownloadStatus.complete) {
      return 'This removes "${job.title}" from Fetchdeck history. The downloaded file is not deleted.';
    }
    if (job.status == DownloadStatus.queued) {
      return 'This removes "${job.title}" from the pending queue before it starts.';
    }
    if (job.status == DownloadStatus.failed) {
      return 'This removes "${job.title}" and its error details from the queue.';
    }
    return 'This removes "${job.title}" from Fetchdeck. You can add the URL again later.';
  }

  String _redownloadTitle(List<_ExistingDownloadTarget> targets) {
    return targets.length == 1
        ? 'Redownload existing file?'
        : 'Redownload existing files?';
  }

  String _redownloadDescription(List<_ExistingDownloadTarget> targets) {
    if (targets.length == 1) {
      return '"${targets.single.title}" already exists on this computer. Redownload it again?';
    }

    return '${targets.length} selected tracks already exist on this computer. Redownload them again?';
  }

  String _reexportTitle(List<_ExistingDownloadTarget> targets) {
    return targets.length == 1
        ? 'Re-export existing segment?'
        : 'Re-export existing segments?';
  }

  String _reexportDescription(List<_ExistingDownloadTarget> targets) {
    if (targets.length == 1) {
      return '"${targets.single.title}" already exists on this computer. Export it again?';
    }

    return '${targets.length} selected split segments already exist on this computer. Export them again?';
  }

  bool _hasSelectedManualSegments(DownloadJob job) {
    return job.children.any(
      (child) =>
          child.kind == DownloadItemKind.manualSegment && child.isSelected,
    );
  }

  bool _pathExists(String? path) {
    if (path == null || path.trim().isEmpty) return false;
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }

  void _setJobFormat(DownloadJob job, String? formatId) {
    actions.setJobFormat(job, formatId);
  }

  void _setStatusMessage(String message) {
    if (!mounted) return;
    ref.read(statusControllerProvider.notifier).setMessage(message);
  }
}

class _ExistingDownloadTarget {
  const _ExistingDownloadTarget._({
    required this.title,
    required this.path,
    this.id,
  });

  factory _ExistingDownloadTarget.job({
    required String title,
    required String path,
  }) {
    return _ExistingDownloadTarget._(title: title, path: path);
  }

  factory _ExistingDownloadTarget.child({
    required String id,
    required String title,
    required String path,
  }) {
    return _ExistingDownloadTarget._(id: id, title: title, path: path);
  }

  final String? id;
  final String title;
  final String path;

  bool get isChild => id != null;
}

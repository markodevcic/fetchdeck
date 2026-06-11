import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'features/downloads/application/queue_controller.dart';
import 'features/shell/application/navigation_controller.dart';
import 'models/download_models.dart';
import 'services/files/file_actions_service.dart';
import 'services/presets/custom_preset_repository.dart';
import 'services/settings/app_settings_repository.dart';
import 'services/tools/bundled_tool_installer.dart';
import 'services/tools/tool_discovery.dart';
import 'services/tools/yt_dlp_update_service.dart';
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

  runApp(const ProviderScope(child: FetchdeckApp()));
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

class DownloadWorkbench extends ConsumerStatefulWidget {
  const DownloadWorkbench({super.key, this.enableToolInspection = true});

  final bool enableToolInspection;

  @override
  ConsumerState<DownloadWorkbench> createState() => _DownloadWorkbenchState();
}

class _DownloadWorkbenchState extends ConsumerState<DownloadWorkbench> {
  final urlController = TextEditingController();
  final toolDiscovery = ToolDiscovery();
  final bundledToolInstaller = const BundledToolInstaller();
  final ytDlpUpdateService = const YtDlpUpdateService();
  final settingsRepository = const AppSettingsRepository();
  final customPresetRepository = const CustomPresetRepository();
  final fileActionsService = const FileActionsService();

  var availablePresets = PresetDefinition.builtIns;
  var selectedPreset = PresetDefinition.defaultPreset;
  var toolSet = const ToolSet.empty();
  var isInspectingTools = true;
  var isAnalyzing = false;
  var isLoadingSettings = true;
  var statusMessage = 'Checking yt-dlp, ffmpeg, and ffprobe...';
  String? outputDirectory;
  String? manualYtDlpPath;
  String? manualFfmpegPath;
  String? manualFfprobePath;
  YtDlpUpdateInfo? ytDlpUpdateInfo;
  var isCheckingYtDlpUpdate = false;
  var isUpdatingYtDlp = false;
  var ytDlpUpdateDismissed = false;
  String lastUrlText = '';
  Timer? pasteAnalyzeDebounce;

  final activeDownloads = <String, YtDlpDownloadSession>{};

  String get selectedSection => ref.read(navigationControllerProvider);

  List<DownloadJob> get visibleJobs {
    return ref.read(queueControllerProvider).visibleJobs(selectedSection);
  }

  String get viewTitle {
    return switch (selectedSection) {
      'Library' => 'Library',
      'Queue' => 'Full Queue',
      _ => 'Downloads',
    };
  }

  String get emptyTitle {
    return switch (selectedSection) {
      'Library' => 'No completed downloads yet',
      'Queue' => 'No queue items yet',
      _ => 'No active downloads yet',
    };
  }

  String get emptyDescription {
    return switch (selectedSection) {
      'Library' =>
        'Completed jobs will stay here after downloads finish, even after restarting the app.',
      'Queue' =>
        'Paste a URL above. Fetchdeck will ask yt-dlp for metadata and add the result here.',
      _ =>
        'Paste a URL above to analyze media, then start downloads from this view.',
    };
  }

  bool get canStartVisibleJobs {
    return ref
        .read(queueControllerProvider)
        .canStartVisibleJobs(selectedSection);
  }

  bool get isSettingsView => selectedSection == 'Settings';

  bool get isPresetsView => selectedSection == 'Presets';

  DownloadJob? get selectedJob {
    return ref.read(queueControllerProvider).selectedJob(selectedSection);
  }

  @override
  void initState() {
    super.initState();
    urlController.addListener(_handleUrlInputChanged);
    if (widget.enableToolInspection) {
      _bootstrap();
    } else {
      isInspectingTools = false;
      isLoadingSettings = false;
      statusMessage = 'Tool inspection skipped for tests.';
    }
  }

  @override
  void dispose() {
    pasteAnalyzeDebounce?.cancel();
    urlController.removeListener(_handleUrlInputChanged);
    for (final session in activeDownloads.values) {
      session.cancel();
    }
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final selectedSection = ref.watch(navigationControllerProvider);
    final queueState = ref.watch(queueControllerProvider);
    final visibleJobs = queueState.visibleJobs(selectedSection);
    final selectedJob = queueState.selectedJob(selectedSection);
    final canStartVisibleJobs = queueState.canStartVisibleJobs(selectedSection);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Row(
          children: [
            _Sidebar(
              selected: selectedSection,
              toolSet: toolSet,
              isInspectingTools: isInspectingTools,
              onSelected: _selectSection,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _Toolbar(
                    controller: urlController,
                    presets: availablePresets,
                    selectedPreset: selectedPreset,
                    isAnalyzing: isAnalyzing,
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
                          ? _SettingsPanel(
                              toolSet: toolSet,
                              ytDlpPath: manualYtDlpPath ?? toolSet.ytDlp.path,
                              ffmpegPath:
                                  manualFfmpegPath ?? toolSet.ffmpeg.path,
                              ffprobePath:
                                  manualFfprobePath ?? toolSet.ffprobe.path,
                              isChecking: isInspectingTools,
                              updateInfo: ytDlpUpdateInfo,
                              isCheckingUpdate: isCheckingYtDlpUpdate,
                              isUpdatingYtDlp: isUpdatingYtDlp,
                              updateDismissed: ytDlpUpdateDismissed,
                              onPickYtDlp: () => _pickToolPath(ToolKind.ytDlp),
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
                              onInstallYtDlpUpdate: _installYtDlpUpdate,
                              onSkipYtDlpUpdate: _skipYtDlpUpdate,
                            )
                          : isPresetsView
                          ? _PresetsPanel(
                              presets: availablePresets,
                              selectedPreset: selectedPreset,
                              onSelected: _setSelectedPreset,
                              onCreate: _createCustomPreset,
                              onDelete: _deleteCustomPreset,
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 7,
                                  child: _QueuePanel(
                                    title: viewTitle,
                                    jobs: visibleJobs,
                                    selectedJobId: queueState.selectedJobId,
                                    hasOutputDirectory: outputDirectory != null,
                                    showStartAll: selectedSection != 'Library',
                                    canStartAll: canStartVisibleJobs,
                                    emptyTitle: emptyTitle,
                                    emptyDescription: emptyDescription,
                                    onSelected: (job) {
                                      ref
                                          .read(
                                            queueControllerProvider.notifier,
                                          )
                                          .selectJob(job.id);
                                    },
                                    onStart: _startDownload,
                                    onCancel: _cancelDownload,
                                    onReveal: _revealOutput,
                                    onRemove: _removeJob,
                                    onStartAll: _startAllDownloads,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  flex: 4,
                                  child: _InspectorPanel(
                                    preset: selectedPreset,
                                    selectedJob: selectedJob,
                                    toolSet: toolSet,
                                    outputDirectory: outputDirectory,
                                    onFormatSelected: _setJobFormat,
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

  Future<void> _bootstrap() async {
    await _loadCustomPresets();
    final settings = await _loadSettings();
    await _loadQueue();
    await _inspectTools(settings);
    if (toolSet.ytDlp.isAvailable) {
      unawaited(_checkYtDlpUpdate(automatic: true));
    }
  }

  void _selectSection(String section) {
    ref.read(navigationControllerProvider.notifier).select(section);
    ref.read(queueControllerProvider.notifier).ensureVisibleSelection(section);
  }

  Future<void> _inspectTools(AppSettings settings) async {
    setState(() {
      isInspectingTools = true;
      statusMessage = 'Checking local tools...';
    });

    final bundledTools = await bundledToolInstaller
        .installCurrentPlatformTools();
    final inspectedTools = await toolDiscovery.inspect(
      preferences: ToolPathPreferences(
        ytDlpPath: settings.ytDlpPath,
        ffmpegPath: settings.ffmpegPath,
        ffprobePath: settings.ffprobePath,
        bundledYtDlpPath: bundledTools.ytDlp,
        bundledYtDlpVersion: bundledTools.ytDlpVersion,
        bundledFfmpegPath: bundledTools.ffmpeg,
        bundledFfmpegVersion: bundledTools.ffmpegVersion,
        bundledFfprobePath: bundledTools.ffprobe,
        bundledFfprobeVersion: bundledTools.ffprobeVersion,
      ),
    );
    if (!mounted) return;

    setState(() {
      toolSet = inspectedTools;
      isInspectingTools = false;
      statusMessage = inspectedTools.ytDlp.isAvailable
          ? 'Ready. yt-dlp found at ${inspectedTools.ytDlp.path}.'
          : _missingYtDlpMessage(inspectedTools.ytDlp);
    });
  }

  Future<AppSettings> _loadSettings() async {
    setState(() {
      isLoadingSettings = true;
      statusMessage = 'Loading saved settings...';
    });

    final settings = await settingsRepository.load();
    final defaultOutputDirectory = await _defaultOutputDirectory();
    if (!mounted) return settings;

    setState(() {
      selectedPreset =
          _presetById(settings.selectedPresetId) ??
          PresetDefinition.defaultPreset;
      outputDirectory = settings.outputDirectory ?? defaultOutputDirectory;
      manualYtDlpPath = settings.ytDlpPath;
      manualFfmpegPath = settings.ffmpegPath;
      manualFfprobePath = settings.ffprobePath;
      isLoadingSettings = false;
      statusMessage = 'Settings loaded.';
    });

    if (settings.outputDirectory == null) {
      await settingsRepository.saveOutputDirectory(defaultOutputDirectory);
    }
    if (settings.selectedPresetId == null) {
      await settingsRepository.saveSelectedPreset(selectedPreset);
    }

    return settings;
  }

  Future<void> _loadQueue() async {
    final restoredCount = await ref
        .read(queueControllerProvider.notifier)
        .load();
    if (!mounted) return;

    if (restoredCount > 0) {
      setState(() => statusMessage = 'Restored $restoredCount saved jobs.');
    }
  }

  Future<String> _defaultOutputDirectory() async {
    final downloads = await getDownloadsDirectory();
    final base = downloads?.path ?? Directory.current.path;
    return '$base/Fetchdeck';
  }

  Future<void> _pickOutputDirectory() async {
    final selectedDirectory = await file_picker.FilePicker.getDirectoryPath(
      dialogTitle: 'Choose output folder',
      initialDirectory: outputDirectory,
    );
    if (selectedDirectory == null || !mounted) return;

    setState(() {
      outputDirectory = selectedDirectory;
      statusMessage = 'Output folder set to $selectedDirectory.';
    });
    await settingsRepository.saveOutputDirectory(selectedDirectory);
  }

  Future<void> _loadCustomPresets() async {
    final customPresets = await customPresetRepository.load();
    if (!mounted) return;

    setState(() {
      availablePresets = [...PresetDefinition.builtIns, ...customPresets];
      selectedPreset = _presetById(selectedPreset.id) ?? selectedPreset;
    });
  }

  PresetDefinition? _presetById(String? id) {
    if (id == null) return null;
    for (final preset in availablePresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  Future<void> _setSelectedPreset(PresetDefinition preset) async {
    setState(() => selectedPreset = preset);
    await settingsRepository.saveSelectedPreset(preset);
  }

  Future<void> _createCustomPreset() async {
    final preset = await showDialog<PresetDefinition>(
      context: context,
      builder: (context) => const _PresetEditorDialog(),
    );
    if (preset == null || !mounted) return;

    setState(() {
      availablePresets = [...availablePresets, preset];
      selectedPreset = preset;
      statusMessage = 'Created preset ${preset.label}.';
    });
    await customPresetRepository.save(availablePresets);
    await settingsRepository.saveSelectedPreset(preset);
  }

  Future<void> _deleteCustomPreset(PresetDefinition preset) async {
    if (preset.isBuiltIn) return;

    setState(() {
      availablePresets = availablePresets
          .where((candidate) => candidate.id != preset.id)
          .toList(growable: false);
      if (selectedPreset.id == preset.id) {
        selectedPreset = PresetDefinition.defaultPreset;
      }
      statusMessage = 'Deleted preset ${preset.label}.';
    });
    await customPresetRepository.save(availablePresets);
    await settingsRepository.saveSelectedPreset(selectedPreset);
  }

  Future<void> _recheckTools() async {
    await _inspectTools(
      AppSettings(
        ytDlpPath: manualYtDlpPath,
        ffmpegPath: manualFfmpegPath,
        ffprobePath: manualFfprobePath,
      ),
    );
  }

  Future<void> _checkYtDlpUpdate({bool automatic = false}) async {
    if (isCheckingYtDlpUpdate || isUpdatingYtDlp) return;

    setState(() {
      isCheckingYtDlpUpdate = true;
      ytDlpUpdateDismissed = false;
      if (!automatic) {
        statusMessage = 'Checking for yt-dlp updates...';
      }
    });

    try {
      final updateInfo = await ytDlpUpdateService.checkForUpdate(
        currentVersion: toolSet.ytDlp.version,
      );
      if (!mounted) return;

      setState(() {
        ytDlpUpdateInfo = updateInfo;
        if (updateInfo.updateAvailable || !automatic) {
          statusMessage = updateInfo.updateAvailable
              ? 'yt-dlp ${updateInfo.latestVersion} is available.'
              : 'yt-dlp is up to date (${updateInfo.latestVersion}).';
        }
      });
    } on YtDlpUpdateException catch (error) {
      if (!mounted) return;
      if (!automatic) {
        setState(() => statusMessage = error.message);
      }
    } catch (error) {
      if (!mounted) return;
      if (!automatic) {
        setState(
          () => statusMessage = 'Could not check yt-dlp updates: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => isCheckingYtDlpUpdate = false);
      }
    }
  }

  Future<void> _installYtDlpUpdate() async {
    if (isUpdatingYtDlp) return;

    setState(() {
      isUpdatingYtDlp = true;
      statusMessage = 'Downloading yt-dlp update...';
    });

    try {
      final result = await ytDlpUpdateService.installLatest();
      if (!mounted) return;

      setState(() {
        statusMessage =
            'Updated yt-dlp to ${result.version}. Re-checking tools...';
        ytDlpUpdateInfo = YtDlpUpdateInfo(
          currentVersion: result.version,
          latestVersion: result.version,
          updateAvailable: false,
        );
        ytDlpUpdateDismissed = false;
      });

      await _recheckTools();
    } on YtDlpUpdateException catch (error) {
      if (!mounted) return;
      setState(() => statusMessage = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => statusMessage = 'Could not update yt-dlp: $error');
    } finally {
      if (mounted) {
        setState(() => isUpdatingYtDlp = false);
      }
    }
  }

  void _skipYtDlpUpdate() {
    setState(() {
      ytDlpUpdateDismissed = true;
      statusMessage = 'Skipped yt-dlp update for now.';
    });
  }

  Future<void> _pickToolPath(ToolKind tool) async {
    final result = await file_picker.FilePicker.pickFiles(
      dialogTitle: 'Choose ${tool.label}',
      initialDirectory: _currentToolPath(tool) == null
          ? null
          : File(_currentToolPath(tool)!).parent.path,
    );
    final files = result?.files;
    final path = files == null || files.isEmpty ? null : files.first.path;
    if (path == null || !mounted) return;

    await _setToolPath(tool, path);
    await _recheckTools();
  }

  Future<void> _setToolPath(ToolKind tool, String? path) async {
    switch (tool) {
      case ToolKind.ytDlp:
        await settingsRepository.saveYtDlpPath(path);
        setState(() => manualYtDlpPath = path);
      case ToolKind.ffmpeg:
        await settingsRepository.saveFfmpegPath(path);
        setState(() => manualFfmpegPath = path);
      case ToolKind.ffprobe:
        await settingsRepository.saveFfprobePath(path);
        setState(() => manualFfprobePath = path);
    }
  }

  Future<void> _clearToolPath(ToolKind tool) async {
    await _setToolPath(tool, null);
    await _recheckTools();
  }

  String? _currentToolPath(ToolKind tool) {
    return switch (tool) {
      ToolKind.ytDlp => manualYtDlpPath ?? toolSet.ytDlp.path,
      ToolKind.ffmpeg => manualFfmpegPath ?? toolSet.ffmpeg.path,
      ToolKind.ffprobe => manualFfprobePath ?? toolSet.ffprobe.path,
    };
  }

  Future<void> _analyzeUrl() async {
    var rawUrl = urlController.text.trim();
    pasteAnalyzeDebounce?.cancel();
    if (rawUrl.isEmpty) {
      rawUrl = await _clipboardUrl();
      if (rawUrl.isNotEmpty) {
        urlController.text = rawUrl;
        lastUrlText = rawUrl;
      } else {
        setState(
          () => statusMessage =
              'Paste a URL into the field, or copy one and press Add again.',
        );
        return;
      }
    }
    if (isAnalyzing) {
      setState(() => statusMessage = 'Already analyzing a URL. Please wait.');
      return;
    }
    if (isInspectingTools || isLoadingSettings) {
      setState(
        () => statusMessage =
            'Still checking local tools. Try again in a moment.',
      );
      return;
    }

    final executable = toolSet.ytDlp.path;
    if (!toolSet.ytDlp.isAvailable || executable == null) {
      setState(() => statusMessage = _cannotUseYtDlpMessage());
      return;
    }

    setState(
      () => statusMessage = 'Add received. Preparing metadata analysis...',
    );

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
      urlController.clear();
      lastUrlText = '';
      statusMessage = 'Running yt-dlp metadata analysis...';
    });
    ref.read(queueControllerProvider.notifier).insertFirst(pendingJob);

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

  void _handleUrlInputChanged() {
    final current = urlController.text.trim();
    final previous = lastUrlText;
    lastUrlText = current;

    if (current.isEmpty || isAnalyzing) {
      pasteAnalyzeDebounce?.cancel();
      return;
    }

    final looksLikePaste = current.length - previous.length > 8;
    if (!looksLikePaste || !_looksLikeUrl(current)) return;

    setState(() => statusMessage = 'Pasted URL detected. Starting analysis...');
    pasteAnalyzeDebounce?.cancel();
    pasteAnalyzeDebounce = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      if (urlController.text.trim() == current && !isAnalyzing) {
        _analyzeUrl();
      }
    });
  }

  bool _looksLikeUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardUrl = await _clipboardUrl();
    if (clipboardUrl.isEmpty) {
      setState(() => statusMessage = 'Clipboard does not contain a URL.');
      return;
    }

    pasteAnalyzeDebounce?.cancel();
    urlController.text = clipboardUrl;
    lastUrlText = clipboardUrl;
    setState(() => statusMessage = 'Pasted URL from clipboard.');
    await _analyzeUrl();
  }

  Future<String> _clipboardUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    return _looksLikeUrl(text) ? text : '';
  }

  void _replaceJob(String id, DownloadJob replacement) {
    ref.read(queueControllerProvider.notifier).replace(id, replacement);
  }

  Future<void> _startAllDownloads() async {
    for (final job in List<DownloadJob>.from(visibleJobs)) {
      if (job.status == DownloadStatus.ready ||
          job.status == DownloadStatus.failed) {
        await _startDownload(job);
      }
    }
  }

  Future<void> _startDownload(DownloadJob job) async {
    if (activeDownloads.containsKey(job.id)) return;

    final executable = toolSet.ytDlp.path;
    final destination = outputDirectory;
    if (!toolSet.ytDlp.isAvailable || executable == null) {
      setState(() => statusMessage = _cannotUseYtDlpMessage());
      return;
    }
    if (destination == null) {
      setState(
        () => statusMessage = 'Choose an output folder before downloading.',
      );
      return;
    }
    if (job.mediaInfo == null) {
      setState(() => statusMessage = 'Analyze the URL before downloading.');
      return;
    }

    await Directory(destination).create(recursive: true);

    _replaceJob(
      job.id,
      job.copyWith(
        status: DownloadStatus.downloading,
        progress: 0,
        eta: 'Starting',
        error: null,
        outputPath: destination,
      ),
    );
    setState(() => statusMessage = 'Starting download: ${job.title}.');

    try {
      final session = await YtDlpService(executable: executable).startDownload(
        url: job.url,
        preset: job.preset,
        outputDirectory: destination,
        isPlaylist: job.mediaInfo!.isPlaylist,
        ffmpegPath: toolSet.ffmpeg.path,
        selectedFormatId: job.selectedFormatId,
      );

      activeDownloads[job.id] = session;
      session.events.listen((event) {
        if (!mounted) return;

        switch (event) {
          case DownloadProgressEvent(:final progress):
            if (!activeDownloads.containsKey(job.id)) return;
            final percent = progress.percent;
            _updateJob(
              job.id,
              (current) => current.copyWith(
                status: DownloadStatus.downloading,
                progress: percent == null ? current.progress : percent / 100,
                eta: progress.label,
                error: null,
                outputPath: destination,
              ),
            );
            setState(() => statusMessage = '${job.title}: ${progress.label}');
          case DownloadCompleteEvent():
            if (activeDownloads.remove(job.id) == null) return;
            _updateJob(
              job.id,
              (current) => current.copyWith(
                status: DownloadStatus.complete,
                progress: 1,
                eta: 'Complete',
                error: null,
                outputPath: destination,
              ),
            );
            setState(() => statusMessage = 'Download complete: ${job.title}.');
          case DownloadErrorEvent(:final message):
            if (activeDownloads.remove(job.id) == null) return;
            _updateJob(
              job.id,
              (current) => current.copyWith(
                status: DownloadStatus.failed,
                eta: 'Failed',
                error: message,
                outputPath: destination,
              ),
            );
            setState(() => statusMessage = message);
        }
      });
    } on YtDlpException catch (error) {
      _replaceJob(
        job.id,
        job.copyWith(
          status: DownloadStatus.failed,
          eta: 'Failed',
          error: error.message,
        ),
      );
      setState(() => statusMessage = error.message);
    } catch (error) {
      _replaceJob(
        job.id,
        job.copyWith(
          status: DownloadStatus.failed,
          eta: 'Failed',
          error: error.toString(),
        ),
      );
      setState(() => statusMessage = 'Unexpected download error: $error');
    }
  }

  void _cancelDownload(DownloadJob job) {
    final session = activeDownloads.remove(job.id);
    session?.cancel();
    _updateJob(
      job.id,
      (current) => current.copyWith(
        status: DownloadStatus.ready,
        eta: 'Cancelled',
        error: null,
      ),
    );
    setState(() => statusMessage = 'Cancelled download: ${job.title}.');
  }

  Future<void> _revealOutput(DownloadJob job) async {
    final path = job.outputPath ?? outputDirectory;
    if (path == null) {
      setState(
        () => statusMessage = 'No output folder is available for ${job.title}.',
      );
      return;
    }

    try {
      await fileActionsService.reveal(path);
      if (!mounted) return;
      setState(() => statusMessage = 'Opened output folder for ${job.title}.');
    } on FileActionException catch (error) {
      if (!mounted) return;
      setState(() => statusMessage = error.message);
    }
  }

  void _removeJob(DownloadJob job) {
    final session = activeDownloads.remove(job.id);
    session?.cancel();

    ref.read(queueControllerProvider.notifier).remove(job, selectedSection);
    setState(() => statusMessage = 'Removed ${job.title}.');
  }

  void _setJobFormat(DownloadJob job, String? formatId) {
    _updateJob(
      job.id,
      (current) => current.copyWith(
        selectedFormatId: formatId,
        clearSelectedFormat: formatId == null,
      ),
    );
    setState(() {
      statusMessage = formatId == null
          ? 'Using preset format selection for ${job.title}.'
          : 'Selected format $formatId for ${job.title}.';
    });
  }

  void _updateJob(String id, DownloadJob Function(DownloadJob current) update) {
    ref.read(queueControllerProvider.notifier).update(id, update);
  }

  String _missingYtDlpMessage(ToolInfo ytDlp) {
    final path = ytDlp.path;
    if (path != null) {
      final detail = ytDlp.error == null ? '' : ' ${ytDlp.error}';
      return 'yt-dlp could not run.$detail';
    }

    return 'yt-dlp was not found. Install it or place yt-dlp/yt-dlp_macos in Downloads, ~/.local/bin, /opt/homebrew/bin, or /usr/local/bin.';
  }

  String _cannotUseYtDlpMessage() {
    final path = toolSet.ytDlp.path;
    if (path != null) {
      final detail = toolSet.ytDlp.error == null
          ? ''
          : ' ${toolSet.ytDlp.error}';
      return 'Cannot analyze yet: yt-dlp could not run.$detail';
    }

    return 'Cannot analyze yet because yt-dlp was not found.';
  }
}

enum ToolKind {
  ytDlp('yt-dlp'),
  ffmpeg('ffmpeg'),
  ffprobe('ffprobe');

  const ToolKind(this.label);

  final String label;
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
    required this.presets,
    required this.selectedPreset,
    required this.isAnalyzing,
    required this.outputDirectory,
    required this.onPresetChanged,
    required this.onAdd,
    required this.onPaste,
    required this.onPickOutput,
  });

  final TextEditingController controller;
  final List<PresetDefinition> presets;
  final PresetDefinition selectedPreset;
  final bool isAnalyzing;
  final String? outputDirectory;
  final ValueChanged<PresetDefinition> onPresetChanged;
  final VoidCallback onAdd;
  final VoidCallback onPaste;
  final VoidCallback onPickOutput;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final inputRow = Row(
            children: [
              Expanded(
                child: _UrlInput(controller: controller, onAdd: onAdd),
              ),
              const SizedBox(width: 8),
              ShadIconButton.outline(
                icon: const Icon(LucideIcons.clipboard, size: 16),
                onPressed: onPaste,
              ),
            ],
          );
          final controlsRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                child: ShadSelect<PresetDefinition>(
                  placeholder: const Text('Preset'),
                  initialValue: selectedPreset,
                  options: [
                    for (final preset in presets)
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
                onPressed: onAdd,
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
                onPressed: onPickOutput,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.folderOpen,
                      size: 16,
                      color: theme.colorScheme.foreground,
                    ),
                    const SizedBox(width: 8),
                    Text(outputDirectory == null ? 'Output' : 'Output Set'),
                  ],
                ),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                inputRow,
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: controlsRow,
                ),
              ] else
                Row(
                  children: [
                    Expanded(child: inputRow),
                    const SizedBox(width: 12),
                    controlsRow,
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _UrlInput extends StatelessWidget {
  const _UrlInput({required this.controller, required this.onAdd});

  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ShadInput(
      controller: controller,
      placeholder: const Text('Paste a video, playlist, channel, or batch URL'),
      leading: const Padding(
        padding: EdgeInsets.only(left: 12),
        child: Icon(LucideIcons.link, size: 16),
      ),
      onSubmitted: (_) => onAdd(),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.toolSet,
    required this.ytDlpPath,
    required this.ffmpegPath,
    required this.ffprobePath,
    required this.isChecking,
    required this.updateInfo,
    required this.isCheckingUpdate,
    required this.isUpdatingYtDlp,
    required this.updateDismissed,
    required this.onPickYtDlp,
    required this.onPickFfmpeg,
    required this.onPickFfprobe,
    required this.onClearYtDlp,
    required this.onClearFfmpeg,
    required this.onClearFfprobe,
    required this.onRecheck,
    required this.onCheckYtDlpUpdate,
    required this.onInstallYtDlpUpdate,
    required this.onSkipYtDlpUpdate,
  });

  final ToolSet toolSet;
  final String? ytDlpPath;
  final String? ffmpegPath;
  final String? ffprobePath;
  final bool isChecking;
  final YtDlpUpdateInfo? updateInfo;
  final bool isCheckingUpdate;
  final bool isUpdatingYtDlp;
  final bool updateDismissed;
  final VoidCallback onPickYtDlp;
  final VoidCallback onPickFfmpeg;
  final VoidCallback onPickFfprobe;
  final VoidCallback onClearYtDlp;
  final VoidCallback onClearFfmpeg;
  final VoidCallback onClearFfprobe;
  final VoidCallback onRecheck;
  final VoidCallback onCheckYtDlpUpdate;
  final VoidCallback onInstallYtDlpUpdate;
  final VoidCallback onSkipYtDlpUpdate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _PageHeader(
          title: 'Settings',
          trailing: ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: isChecking ? null : onRecheck,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isChecking ? LucideIcons.loaderCircle : LucideIcons.refreshCw,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(isChecking ? 'Checking' : 'Re-check Tools'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: 'Tool Paths',
          children: [
            _ToolPathRow(
              label: 'yt-dlp',
              path: ytDlpPath,
              info: toolSet.ytDlp,
              onChoose: onPickYtDlp,
              onClear: onClearYtDlp,
            ),
            const SizedBox(height: 10),
            _ToolPathRow(
              label: 'ffmpeg',
              path: ffmpegPath,
              info: toolSet.ffmpeg,
              onChoose: onPickFfmpeg,
              onClear: onClearFfmpeg,
            ),
            const SizedBox(height: 10),
            _ToolPathRow(
              label: 'ffprobe',
              path: ffprobePath,
              info: toolSet.ffprobe,
              onChoose: onPickFfprobe,
              onClear: onClearFfprobe,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: 'Tool Updates',
          children: [
            _YtDlpUpdateRow(
              toolInfo: toolSet.ytDlp,
              updateInfo: updateInfo,
              isChecking: isCheckingUpdate,
              isUpdating: isUpdatingYtDlp,
              updateDismissed: updateDismissed,
              onCheck: onCheckYtDlpUpdate,
              onUpdate: onInstallYtDlpUpdate,
              onSkip: onSkipYtDlpUpdate,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: 'Engine Strategy',
          children: [
            _InlineFact(
              icon: LucideIcons.terminal,
              text:
                  'Fetchdeck calls yt-dlp through Process.start with structured arguments and progress templates.',
            ),
            const SizedBox(height: 10),
            _InlineFact(
              icon: LucideIcons.folderOpen,
              text:
                  'Downloads use the selected output folder and user-selected macOS file access.',
            ),
          ],
        ),
      ],
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.h4)),
          ?trailing,
        ],
      ),
    );
  }
}

class _InlineFact extends StatelessWidget {
  const _InlineFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.mutedForeground),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.muted)),
      ],
    );
  }
}

class _PresetsPanel extends StatelessWidget {
  const _PresetsPanel({
    required this.presets,
    required this.selectedPreset,
    required this.onSelected,
    required this.onCreate,
    required this.onDelete,
  });

  final List<PresetDefinition> presets;
  final PresetDefinition selectedPreset;
  final ValueChanged<PresetDefinition> onSelected;
  final VoidCallback onCreate;
  final ValueChanged<PresetDefinition> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 38,
          child: Row(
            children: [
              Expanded(child: Text('Presets', style: theme.textTheme.h4)),
              SizedBox(
                width: 180,
                child: ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: onCreate,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.plus, size: 15),
                      SizedBox(width: 6),
                      Text('New Preset'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: ListView.separated(
                  itemCount: presets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final preset = presets[index];
                    return _PresetRow(
                      preset: preset,
                      selected: preset == selectedPreset,
                      onPressed: () => onSelected(preset),
                    );
                  },
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: _PresetDetails(
                  preset: selectedPreset,
                  onDelete: selectedPreset.isBuiltIn
                      ? null
                      : () => onDelete(selectedPreset),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.preset,
    required this.selected,
    required this.onPressed,
  });

  final PresetDefinition preset;
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
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.muted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                preset.looksAudio ? LucideIcons.audioLines : LucideIcons.video,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preset.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (selected)
              Icon(
                LucideIcons.circleCheck,
                size: 18,
                color: const Color(0xFF15803D),
              ),
          ],
        ),
      ),
    );
  }
}

class _PresetDetails extends StatelessWidget {
  const _PresetDetails({required this.preset, required this.onDelete});

  final PresetDefinition preset;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Selected Preset', style: theme.textTheme.large),
          const SizedBox(height: 6),
          Text(preset.label, style: theme.textTheme.muted),
          const SizedBox(height: 10),
          _PresetTypeBadge(isBuiltIn: preset.isBuiltIn),
          const SizedBox(height: 16),
          Text('Arguments', style: theme.textTheme.small),
          const SizedBox(height: 8),
          _ArgumentsPreview(arguments: preset.arguments),
          const SizedBox(height: 16),
          Text('Command Summary', style: theme.textTheme.small),
          const SizedBox(height: 8),
          Container(
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
          ),
          if (onDelete != null) ...[
            const Spacer(),
            ShadButton.destructive(
              onPressed: onDelete,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.trash2, size: 15),
                  SizedBox(width: 6),
                  Text('Delete Preset'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetTypeBadge extends StatelessWidget {
  const _PresetTypeBadge({required this.isBuiltIn});

  final bool isBuiltIn;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isBuiltIn ? 'Built-in' : 'Custom',
        style: theme.textTheme.small,
      ),
    );
  }
}

class _PresetEditorDialog extends StatefulWidget {
  const _PresetEditorDialog();

  @override
  State<_PresetEditorDialog> createState() => _PresetEditorDialogState();
}

class _PresetEditorDialogState extends State<_PresetEditorDialog> {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final argumentsController = TextEditingController();
  String? error;

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    argumentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return AlertDialog(
      title: const Text('New Preset'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShadInput(
              controller: nameController,
              placeholder: const Text('Preset name'),
            ),
            const SizedBox(height: 10),
            ShadInput(
              controller: descriptionController,
              placeholder: const Text('Short description'),
            ),
            const SizedBox(height: 10),
            Text('Arguments', style: theme.textTheme.small),
            const SizedBox(height: 6),
            TextField(
              controller: argumentsController,
              minLines: 6,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '-f\nba\n-x\n--audio-format\nmp3',
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: theme.textTheme.small.copyWith(
                  color: const Color(0xFFB91C1C),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }

  void _submit() {
    final label = nameController.text.trim();
    final arguments = argumentsController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (label.isEmpty) {
      setState(() => error = 'Name is required.');
      return;
    }
    if (arguments.isEmpty) {
      setState(() => error = 'At least one yt-dlp argument is required.');
      return;
    }

    Navigator.of(context).pop(
      PresetDefinition(
        id: 'custom:${DateTime.now().microsecondsSinceEpoch}',
        label: label,
        description: descriptionController.text.trim().isEmpty
            ? 'Custom yt-dlp preset.'
            : descriptionController.text.trim(),
        commandSummary: arguments.join(' '),
        arguments: arguments,
        isBuiltIn: false,
      ),
    );
  }
}

class _ArgumentsPreview extends StatelessWidget {
  const _ArgumentsPreview({required this.arguments});

  final List<String> arguments;

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
      child: SelectableText(
        arguments.join('\n'),
        style: theme.textTheme.small.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.large),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _ToolPathRow extends StatelessWidget {
  const _ToolPathRow({
    required this.label,
    required this.path,
    required this.info,
    required this.onChoose,
    required this.onClear,
  });

  final String label;
  final String? path;
  final ToolInfo info;
  final VoidCallback onChoose;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final healthy = info.isAvailable;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            healthy ? LucideIcons.circleCheck : LucideIcons.circleAlert,
            size: 17,
            color: healthy
                ? const Color(0xFF15803D)
                : theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: theme.textTheme.small),
                    const SizedBox(width: 8),
                    Text(
                      healthy
                          ? 'Available • ${info.source?.label ?? 'System'}'
                          : info.path == null
                          ? 'Missing'
                          : 'Blocked • ${info.source?.label ?? 'Unknown'}',
                      style: theme.textTheme.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  info.path ??
                      path ??
                      'Auto-detect bundled tools, PATH, and common install folders',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.muted,
                ),
                if (info.version != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    info.version!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.small,
                  ),
                ],
                if (!info.isAvailable && info.error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    info.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.small,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: onChoose,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.folderOpen, size: 15),
                SizedBox(width: 6),
                Text('Choose'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.x, size: 16),
            onPressed: path == null ? null : onClear,
          ),
        ],
      ),
    );
  }
}

class _YtDlpUpdateRow extends StatelessWidget {
  const _YtDlpUpdateRow({
    required this.toolInfo,
    required this.updateInfo,
    required this.isChecking,
    required this.isUpdating,
    required this.updateDismissed,
    required this.onCheck,
    required this.onUpdate,
    required this.onSkip,
  });

  final ToolInfo toolInfo;
  final YtDlpUpdateInfo? updateInfo;
  final bool isChecking;
  final bool isUpdating;
  final bool updateDismissed;
  final VoidCallback onCheck;
  final VoidCallback onUpdate;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final updateAvailable =
        updateInfo?.updateAvailable == true && !updateDismissed;
    final currentVersion = updateInfo?.currentVersion ?? toolInfo.version;
    final latestVersion = updateInfo?.latestVersion;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            updateAvailable
                ? LucideIcons.circleArrowUp
                : LucideIcons.circleCheck,
            size: 17,
            color: updateAvailable
                ? const Color(0xFFB45309)
                : const Color(0xFF15803D),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('yt-dlp', style: theme.textTheme.small),
                    const SizedBox(width: 8),
                    Text(
                      updateAvailable ? 'Update available' : 'Updates',
                      style: theme.textTheme.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _versionText(currentVersion, latestVersion, updateDismissed),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.muted,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (updateAvailable) ...[
            ShadButton(
              size: ShadButtonSize.sm,
              onPressed: isUpdating ? null : onUpdate,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUpdating
                        ? LucideIcons.loaderCircle
                        : LucideIcons.download,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Text(isUpdating ? 'Updating' : 'Update'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: isUpdating ? null : onSkip,
              child: const Text('Skip'),
            ),
          ] else
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: isChecking || isUpdating ? null : onCheck,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isChecking
                        ? LucideIcons.loaderCircle
                        : LucideIcons.refreshCw,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Text(isChecking ? 'Checking' : 'Check'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _versionText(
    String? currentVersion,
    String? latestVersion,
    bool dismissed,
  ) {
    final current = currentVersion ?? 'unknown';
    if (latestVersion == null) return 'Current version: $current';
    if (dismissed) {
      return 'Current version: $current. Latest $latestVersion skipped for now.';
    }
    return 'Current version: $current. Latest version: $latestVersion.';
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.title,
    required this.jobs,
    required this.selectedJobId,
    required this.hasOutputDirectory,
    required this.showStartAll,
    required this.canStartAll,
    required this.emptyTitle,
    required this.emptyDescription,
    required this.onSelected,
    required this.onStart,
    required this.onCancel,
    required this.onReveal,
    required this.onRemove,
    required this.onStartAll,
  });

  final String title;
  final List<DownloadJob> jobs;
  final String? selectedJobId;
  final bool hasOutputDirectory;
  final bool showStartAll;
  final bool canStartAll;
  final String emptyTitle;
  final String emptyDescription;
  final ValueChanged<DownloadJob> onSelected;
  final ValueChanged<DownloadJob> onStart;
  final ValueChanged<DownloadJob> onCancel;
  final ValueChanged<DownloadJob> onReveal;
  final ValueChanged<DownloadJob> onRemove;
  final VoidCallback onStartAll;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 38,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text(title, style: theme.textTheme.h4)),
              SizedBox(
                width: 180,
                child: showStartAll
                    ? ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: !canStartAll || !hasOutputDirectory
                            ? null
                            : onStartAll,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.play, size: 15),
                            SizedBox(width: 6),
                            Text('Start All'),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: jobs.isEmpty
              ? _EmptyQueue(title: emptyTitle, description: emptyDescription)
              : ListView.separated(
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return _JobRow(
                      job: job,
                      selected: selectedJobId == job.id,
                      onPressed: () => onSelected(job),
                      onStart: () => onStart(job),
                      onCancel: () => onCancel(job),
                      onReveal: () => onReveal(job),
                      onRemove: () => onRemove(job),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.title, required this.description});

  final String title;
  final String description;

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
            Text(title, style: theme.textTheme.large),
            const SizedBox(height: 6),
            Text(
              description,
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
    required this.onStart,
    required this.onCancel,
    required this.onReveal,
    required this.onRemove,
  });

  final DownloadJob job;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onReveal;
  final VoidCallback onRemove;

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
            if (job.status == DownloadStatus.complete) ...[
              ShadIconButton.ghost(
                icon: const Icon(LucideIcons.folderOpen, size: 17),
                onPressed: onReveal,
              ),
              const SizedBox(width: 4),
            ],
            ShadIconButton.ghost(
              icon: Icon(
                job.status == DownloadStatus.downloading
                    ? LucideIcons.square
                    : LucideIcons.download,
                size: 17,
              ),
              onPressed:
                  job.status == DownloadStatus.analyzing ||
                      job.status == DownloadStatus.complete
                  ? null
                  : job.status == DownloadStatus.downloading
                  ? onCancel
                  : onStart,
            ),
            const SizedBox(width: 4),
            ShadIconButton.ghost(
              icon: const Icon(LucideIcons.trash2, size: 17),
              onPressed: job.status == DownloadStatus.downloading
                  ? null
                  : onRemove,
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
    required this.outputDirectory,
    required this.onFormatSelected,
  });

  final PresetDefinition preset;
  final DownloadJob? selectedJob;
  final ToolSet toolSet;
  final String? outputDirectory;
  final void Function(DownloadJob job, String? formatId) onFormatSelected;

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
                    label: 'Output',
                    value:
                        selectedJob?.outputPath ?? outputDirectory ?? 'Not set',
                  ),
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
    final theme = ShadTheme.of(context);
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
            Text('Format', style: theme.textTheme.small),
            const SizedBox(width: 8),
            Text('${formats.length} available', style: theme.textTheme.muted),
          ],
        ),
        const SizedBox(height: 6),
        ShadSelect<String>(
          placeholder: const Text('Preset decides'),
          initialValue: selectedFormat,
          options: [
            const ShadOption(value: '', child: Text('Preset decides')),
            for (final entry in groupedFormats.entries) ...[
              ShadOption(
                value: '__header_${entry.key.name}',
                child: Text('${entry.key.label} (${entry.value.length})'),
              ),
              for (final format in entry.value)
                ShadOption(value: format.id, child: Text(format.displayLabel)),
            ],
          ],
          selectedOptionBuilder: (context, value) {
            if (value.isEmpty) return const Text('Preset decides');
            final format = formats.firstWhere(
              (candidate) => candidate.id == value,
              orElse: () => MediaFormat(id: value, label: value),
            );
            return Text(format.displayLabel);
          },
          onChanged: (value) => onChanged(
            value == null || value.isEmpty || value.startsWith('__header_')
                ? null
                : value,
          ),
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

class _CommandPreview extends StatelessWidget {
  const _CommandPreview({required this.preset});

  final PresetDefinition preset;

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

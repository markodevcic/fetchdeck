import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';
import 'package:yt_dlp_desktop/features/downloads/application/queue_controller.dart';
import 'package:yt_dlp_desktop/features/downloads/presentation/queue_panel.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';

void main() {
  testWidgets('only enables split action for local downloaded audio', (
    tester,
  ) async {
    var splitCount = 0;
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_panel_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final downloadedFile = File('${tempDirectory.path}/downloaded.mp3')
      ..writeAsStringSync('audio');

    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 560,
            child: QueuePanel(
              title: 'Downloads',
              jobs: [_analyzedJob(), _downloadedJob(downloadedFile.path)],
              selectedJobId: null,
              hasOutputDirectory: true,
              canStartAll: true,
              statusFilter: QueueStatusFilter.all,
              searchQuery: '',
              onSelected: (_) {},
              onStart: (_) {},
              onCancel: (_) {},
              onSplit: (_) => splitCount += 1,
              onReveal: (_) {},
              onRemove: (_) {},
              onStartAll: () {},
              onStatusFilterChanged: (_) {},
              onSearchChanged: (_) {},
              onToggleExpanded: (_) {},
              onChildSelected:
                  ({required job, required child, required isSelected}) {},
              onSelectAllChildren: ({required job, required isSelected}) {},
            ),
          ),
        ),
      ),
    );

    final scissors = find.byIcon(LucideIcons.scissors);
    expect(scissors, findsNWidgets(2));
    expect(find.byIcon(LucideIcons.download), findsNWidgets(2));

    await tester.tap(scissors.first, warnIfMissed: false);
    await _pumpForuiButtonAnimations(tester);
    expect(splitCount, 0);

    await tester.tap(scissors.last);
    await _pumpForuiButtonAnimations(tester);
    expect(splitCount, 1);
  });

  testWidgets('only enables reveal action when completed output exists', (
    tester,
  ) async {
    var revealCount = 0;
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_panel_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final downloadedFile = File('${tempDirectory.path}/downloaded.mp3')
      ..writeAsStringSync('audio');

    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 560,
            child: QueuePanel(
              title: 'Downloads',
              jobs: [
                _downloadedJob(
                  '${tempDirectory.path}/missing.mp3',
                  id: 'job-1',
                ),
                _downloadedJob(downloadedFile.path, id: 'job-2'),
              ],
              selectedJobId: null,
              hasOutputDirectory: true,
              canStartAll: true,
              statusFilter: QueueStatusFilter.all,
              searchQuery: '',
              onSelected: (_) {},
              onStart: (_) {},
              onCancel: (_) {},
              onSplit: (_) {},
              onReveal: (_) => revealCount += 1,
              onRemove: (_) {},
              onStartAll: () {},
              onStatusFilterChanged: (_) {},
              onSearchChanged: (_) {},
              onToggleExpanded: (_) {},
              onChildSelected:
                  ({required job, required child, required isSelected}) {},
              onSelectAllChildren: ({required job, required isSelected}) {},
            ),
          ),
        ),
      ),
    );

    final folders = find.byIcon(LucideIcons.folderOpen);
    expect(folders, findsNWidgets(2));

    await tester.tap(folders.first, warnIfMissed: false);
    await _pumpForuiButtonAnimations(tester);
    expect(revealCount, 0);

    await tester.tap(folders.last);
    await _pumpForuiButtonAnimations(tester);
    expect(revealCount, 1);
  });

  testWidgets('shows export action for selected split segments', (
    tester,
  ) async {
    var startCount = 0;
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_panel_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final sourceFile = File('${tempDirectory.path}/source.mp3')
      ..writeAsStringSync('audio');

    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 560,
            child: QueuePanel(
              title: 'Downloads',
              jobs: [_splitJob(sourceFile.path)],
              selectedJobId: null,
              hasOutputDirectory: true,
              canStartAll: true,
              statusFilter: QueueStatusFilter.all,
              searchQuery: '',
              onSelected: (_) {},
              onStart: (_) => startCount += 1,
              onCancel: (_) {},
              onSplit: (_) {},
              onReveal: (_) {},
              onRemove: (_) {},
              onStartAll: () {},
              onStatusFilterChanged: (_) {},
              onSearchChanged: (_) {},
              onToggleExpanded: (_) {},
              onChildSelected:
                  ({required job, required child, required isSelected}) {},
              onSelectAllChildren: ({required job, required isSelected}) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(LucideIcons.fileOutput), findsOneWidget);
    expect(find.text('Exported'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.fileOutput));
    await _pumpForuiButtonAnimations(tester);
    expect(startCount, 1);
  });

  testWidgets('shows download action when selected split source is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 560,
            child: QueuePanel(
              title: 'Downloads',
              jobs: [_splitJob('/tmp/fetchdeck_missing_source.mp3')],
              selectedJobId: null,
              hasOutputDirectory: true,
              canStartAll: true,
              statusFilter: QueueStatusFilter.all,
              searchQuery: '',
              onSelected: (_) {},
              onStart: (_) {},
              onCancel: (_) {},
              onSplit: (_) {},
              onReveal: (_) {},
              onRemove: (_) {},
              onStartAll: () {},
              onStatusFilterChanged: (_) {},
              onSearchChanged: (_) {},
              onToggleExpanded: (_) {},
              onChildSelected:
                  ({required job, required child, required isSelected}) {},
              onSelectAllChildren: ({required job, required isSelected}) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(LucideIcons.fileOutput), findsNothing);
    expect(find.byIcon(LucideIcons.download), findsOneWidget);
  });

  testWidgets('locks expanded track selection while a segment is exporting', (
    tester,
  ) async {
    var selectionChanges = 0;
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_panel_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final sourceFile = File('${tempDirectory.path}/source.mp3')
      ..writeAsStringSync('audio');

    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 560,
            child: QueuePanel(
              title: 'Downloads',
              jobs: [_activeSplitJob(sourceFile.path)],
              selectedJobId: null,
              hasOutputDirectory: true,
              canStartAll: true,
              statusFilter: QueueStatusFilter.all,
              searchQuery: '',
              onSelected: (_) {},
              onStart: (_) {},
              onCancel: (_) {},
              onSplit: (_) {},
              onReveal: (_) {},
              onRemove: (_) {},
              onStartAll: () {},
              onStatusFilterChanged: (_) {},
              onSearchChanged: (_) {},
              onToggleExpanded: (_) {},
              onChildSelected:
                  ({required job, required child, required isSelected}) =>
                      selectionChanges += 1,
              onSelectAllChildren: ({required job, required isSelected}) {},
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Track 01'));
    expect(title.style?.fontWeight, FontWeight.w800);
    expect(find.text('Selection locked'), findsOneWidget);
    expect(find.byIcon(LucideIcons.squareCheck), findsNothing);
    expect(find.byIcon(LucideIcons.square), findsNothing);
    expect(find.byIcon(LucideIcons.loaderCircle), findsOneWidget);
    expect(find.text('Exporting'), findsOneWidget);

    await tester.tap(find.text('Track 01'));
    expect(selectionChanges, 0);
  });

  testWidgets('shows orange download action for stopped jobs', (tester) async {
    var startCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 560,
            child: QueuePanel(
              title: 'Downloads',
              jobs: [_stoppedJob()],
              selectedJobId: null,
              hasOutputDirectory: true,
              canStartAll: true,
              statusFilter: QueueStatusFilter.all,
              searchQuery: '',
              onSelected: (_) {},
              onStart: (_) => startCount += 1,
              onCancel: (_) {},
              onSplit: (_) {},
              onReveal: (_) {},
              onRemove: (_) {},
              onStartAll: () {},
              onStatusFilterChanged: (_) {},
              onSearchChanged: (_) {},
              onToggleExpanded: (_) {},
              onChildSelected:
                  ({required job, required child, required isSelected}) {},
              onSelectAllChildren: ({required job, required isSelected}) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Stopped by user'), findsOneWidget);
    expect(find.byIcon(LucideIcons.download), findsOneWidget);
    expect(find.byIcon(LucideIcons.rotateCcw), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.download));
    await _pumpForuiButtonAnimations(tester);
    expect(startCount, 1);
  });

  testWidgets('labels unselected expanded tracks as skipped', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 560,
            child: QueuePanel(
              title: 'Downloads',
              jobs: [_playlistJobWithSkippedTrack()],
              selectedJobId: null,
              hasOutputDirectory: true,
              canStartAll: true,
              statusFilter: QueueStatusFilter.all,
              searchQuery: '',
              onSelected: (_) {},
              onStart: (_) {},
              onCancel: (_) {},
              onSplit: (_) {},
              onReveal: (_) {},
              onRemove: (_) {},
              onStartAll: () {},
              onStatusFilterChanged: (_) {},
              onSearchChanged: (_) {},
              onToggleExpanded: (_) {},
              onChildSelected:
                  ({required job, required child, required isSelected}) {},
              onSelectAllChildren: ({required job, required isSelected}) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Track 01'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.byIcon(LucideIcons.circleMinus), findsOneWidget);
  });
}

Future<void> _pumpForuiButtonAnimations(WidgetTester tester) {
  return tester.pump(const Duration(milliseconds: 150));
}

DownloadJob _analyzedJob() {
  return DownloadJob(
    id: 'job-1',
    url: 'https://example.com/analyzed',
    title: 'Analyzed Only',
    source: 'Example',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.ready,
    progress: 0,
    eta: 'Ready',
    mediaInfo: const MediaInfo(
      title: 'Analyzed Only',
      webpageUrl: 'https://example.com/analyzed',
      extractor: 'Example',
      formatCount: 1,
      duration: Duration(minutes: 10),
    ),
  );
}

DownloadJob _downloadedJob(String downloadedFilePath, {String id = 'job-2'}) {
  return DownloadJob(
    id: id,
    url: 'https://example.com/downloaded',
    title: 'Downloaded Audio',
    source: 'Example',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.complete,
    progress: 1,
    eta: 'Complete',
    downloadedFilePath: downloadedFilePath,
    mediaInfo: const MediaInfo(
      title: 'Downloaded Audio',
      webpageUrl: 'https://example.com/downloaded',
      extractor: 'Example',
      formatCount: 1,
      duration: Duration(minutes: 10),
    ),
  );
}

DownloadJob _stoppedJob() {
  return DownloadJob(
    id: 'job-stopped',
    url: 'https://example.com/stopped',
    title: 'Stopped Audio',
    source: 'Example',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.stopped,
    progress: 0.4,
    eta: 'Stopped',
    mediaInfo: const MediaInfo(
      title: 'Stopped Audio',
      webpageUrl: 'https://example.com/stopped',
      extractor: 'Example',
      formatCount: 1,
      duration: Duration(minutes: 10),
    ),
  );
}

DownloadJob _splitJob(String sourceFilePath) {
  return DownloadJob(
    id: 'job-3',
    url: 'https://example.com/downloaded',
    title: 'Downloaded Audio',
    source: 'Example',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.complete,
    progress: 1,
    eta: 'Complete',
    downloadedFilePath: sourceFilePath,
    splitSourceFilePath: sourceFilePath,
    isExpanded: true,
    mediaInfo: const MediaInfo(
      title: 'Downloaded Audio',
      webpageUrl: 'https://example.com/downloaded',
      extractor: 'Example',
      formatCount: 1,
      duration: Duration(minutes: 10),
    ),
    children: const [
      DownloadItem(
        id: 'segment-1',
        kind: DownloadItemKind.manualSegment,
        title: 'Track 01',
        status: DownloadStatus.ready,
        progress: 0,
        isSelected: true,
        startTime: Duration.zero,
        endTime: Duration(minutes: 5),
      ),
    ],
  );
}

DownloadJob _activeSplitJob(String sourceFilePath) {
  final job = _splitJob(sourceFilePath);
  return job.copyWith(
    children: [
      job.children.first.copyWith(
        status: DownloadStatus.downloading,
        progress: 0.45,
      ),
    ],
  );
}

DownloadJob _playlistJobWithSkippedTrack() {
  return DownloadJob(
    id: 'job-playlist',
    url: 'https://example.com/playlist',
    title: 'Playlist',
    source: 'Example',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.ready,
    progress: 0,
    eta: 'Ready',
    isExpanded: true,
    mediaInfo: const MediaInfo(
      title: 'Playlist',
      webpageUrl: 'https://example.com/playlist',
      extractor: 'Example',
      formatCount: 1,
      duration: Duration(minutes: 10),
    ),
    children: const [
      DownloadItem(
        id: 'track-1',
        kind: DownloadItemKind.playlistEntry,
        title: 'Track 01',
        status: DownloadStatus.ready,
        progress: 0,
        isSelected: false,
      ),
    ],
  );
}

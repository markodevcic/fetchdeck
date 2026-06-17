import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';
import 'package:yt_dlp_desktop/features/downloads/presentation/inspector_panel.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';

void main() {
  testWidgets('shows selected job details and errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 720,
            child: InspectorPanel(
              preset: PresetDefinition.defaultPreset,
              selectedJob: _job(),
              outputDirectory: '/downloads/Fetchdeck',
              onFormatSelected: (_, _) {},
              onRetry: (_) {},
              onReveal: (_) {},
              onOpenFullDiskAccessSettings: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Job Details'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Failed'), findsWidgets);
    expect(find.text('Custom MP3'), findsOneWidget);
    expect(find.text('Network error'), findsOneWidget);
    expect(find.text('Log'), findsOneWidget);
    expect(find.text('Download started.'), findsOneWidget);
    expect(find.text('Download failed: Network error'), findsOneWidget);
    expect(find.textContaining('https://example.com/video'), findsOneWidget);
  });

  testWidgets('shows completed file actions and history', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 720,
            child: InspectorPanel(
              preset: PresetDefinition.defaultPreset,
              selectedJob: _completedJob(),
              outputDirectory: '/downloads/Fetchdeck',
              onFormatSelected: (_, _) {},
              onRetry: (_) {},
              onReveal: (_) {},
              onOpenFullDiskAccessSettings: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Complete'), findsWidgets);
    expect(find.text('Started'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('4m'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('3.00 MB'), findsOneWidget);
    expect(find.text('/downloads/Fetchdeck/example.mp3'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    expect(find.text('Show in Folder'), findsOneWidget);
  });

  testWidgets('shows child work summary for playlist jobs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 720,
            child: InspectorPanel(
              preset: PresetDefinition.defaultPreset,
              selectedJob: _childJob(),
              outputDirectory: '/downloads/Fetchdeck',
              onFormatSelected: (_, _) {},
              onRetry: (_) {},
              onReveal: (_) {},
              onOpenFullDiskAccessSettings: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Items'), findsOneWidget);
    expect(
      find.text('2 selected • 1 active • 1 complete • 1 failed'),
      findsOneWidget,
    );
  });

  testWidgets('shows Full Disk Access action for Safari cookie errors', (
    tester,
  ) async {
    var openedSettings = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 720,
            child: InspectorPanel(
              preset: PresetDefinition.defaultPreset,
              selectedJob: _job().copyWith(
                error:
                    'macOS blocked access to Safari cookies. Grant Full Disk Access to Fetchdeck in System Settings.',
              ),
              outputDirectory: '/downloads/Fetchdeck',
              onFormatSelected: (_, _) {},
              onRetry: (_) {},
              onReveal: (_) {},
              onOpenFullDiskAccessSettings: () => openedSettings = true,
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Open Full Disk Access'));
    await tester.tap(find.text('Open Full Disk Access'));
    await _pumpForuiButtonAnimations(tester);
    expect(openedSettings, isTrue);
  });
}

Future<void> _pumpForuiButtonAnimations(WidgetTester tester) {
  return tester.pump(const Duration(milliseconds: 150));
}

DownloadJob _job() {
  return const DownloadJob(
    id: 'job-1',
    url: 'https://example.com/video',
    title: 'Example Video',
    source: 'example.com',
    preset: PresetDefinition(
      id: 'custom:mp3',
      label: 'Custom MP3',
      description: 'Custom preset',
      commandSummary: '-x --audio-format mp3',
      arguments: ['-x', '--audio-format', 'mp3'],
      isBuiltIn: false,
    ),
    status: DownloadStatus.failed,
    progress: 0.42,
    eta: 'Failed',
    error: 'Network error',
    outputPath: '/downloads/Fetchdeck',
    logLines: ['Download started.', 'Download failed: Network error'],
  );
}

DownloadJob _completedJob() {
  return DownloadJob(
    id: 'job-2',
    url: 'https://example.com/audio',
    title: 'Example Audio',
    source: 'example.com',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.complete,
    progress: 1,
    eta: 'Complete',
    outputPath: '/downloads/Fetchdeck',
    downloadedFilePath: '/downloads/Fetchdeck/example.mp3',
    downloadedFileSize: 3145728,
    startedAt: DateTime.utc(2026, 6, 12, 10, 30),
    completedAt: DateTime.utc(2026, 6, 12, 10, 34),
    logLines: const ['Download started.', 'Download complete.'],
  );
}

DownloadJob _childJob() {
  return DownloadJob(
    id: 'job-3',
    url: 'https://example.com/playlist',
    title: 'Example Playlist',
    source: 'example.com',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.downloading,
    progress: 0.5,
    eta: 'Downloading 2 of 3',
    children: const [
      DownloadItem(
        id: 'entry:1',
        kind: DownloadItemKind.playlistEntry,
        title: 'One',
        status: DownloadStatus.complete,
        progress: 1,
      ),
      DownloadItem(
        id: 'entry:2',
        kind: DownloadItemKind.playlistEntry,
        title: 'Two',
        status: DownloadStatus.downloading,
        progress: 0.5,
      ),
      DownloadItem(
        id: 'entry:3',
        kind: DownloadItemKind.playlistEntry,
        title: 'Three',
        status: DownloadStatus.failed,
        progress: 0,
        isSelected: false,
        error: 'Unavailable',
      ),
    ],
  );
}

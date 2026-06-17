import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';
import 'package:yt_dlp_desktop/features/split_editor/application/split_audio_controller.dart';
import 'package:yt_dlp_desktop/features/split_editor/application/split_editor_controller.dart';
import 'package:yt_dlp_desktop/features/split_editor/presentation/split_editor_drawer.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';

void main() {
  testWidgets('renders split editor shell for a job', (tester) async {
    final container = ProviderContainer(
      overrides: [splitAudioAutoloadEnabledProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);
    container.read(splitEditorControllerProvider.notifier).open(_job());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: fetchdeckMaterialTheme(Brightness.dark),
          home: Scaffold(
            body: SplitEditorDrawer(job: _job(), onClose: () {}),
          ),
        ),
      ),
    );

    expect(find.text('Split Editor'), findsOneWidget);
    expect(find.text('Long Worship Mix'), findsOneWidget);
    expect(find.text('Add Marker'), findsOneWidget);
    expect(find.text('Detect'), findsOneWidget);
    expect(find.text('Scan Balanced'), findsOneWidget);
    expect(find.text('Fade: Off'), findsOneWidget);
    expect(find.text('Track 01'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('disables add marker when playhead is already marked', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [splitAudioAutoloadEnabledProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);
    container.read(splitEditorControllerProvider.notifier).open(_job());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: fetchdeckMaterialTheme(Brightness.dark),
          home: Scaffold(
            body: SplitEditorDrawer(job: _job(), onClose: () {}),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add Marker'));
    await tester.pump(const Duration(milliseconds: 150));

    expect(container.read(splitEditorControllerProvider).markers, hasLength(1));
  });
}

DownloadJob _job() {
  return DownloadJob(
    id: 'job-1',
    url: 'https://example.com/video',
    title: 'Long Worship Mix',
    source: 'Example',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.ready,
    progress: 0,
    eta: 'Ready',
    downloadedFilePath: '/tmp/source.mp3',
    mediaInfo: const MediaInfo(
      title: 'Long Worship Mix',
      webpageUrl: 'https://example.com/video',
      extractor: 'Example',
      formatCount: 1,
      duration: Duration(minutes: 42),
    ),
  );
}

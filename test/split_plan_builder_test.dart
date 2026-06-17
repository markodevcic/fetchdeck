import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/split_editor/application/split_plan_builder.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';

void main() {
  test('builds manual segment children from named song-start markers', () {
    final result = const SplitPlanBuilder().build(
      sourceFilePath: '/tmp/source.mp3',
      duration: const Duration(minutes: 12),
      markers: const [
        SplitMarker(
          id: 'marker-2',
          position: Duration(minutes: 7),
          title: 'Blessed Assurance',
        ),
        SplitMarker(
          id: 'marker-1',
          position: Duration(minutes: 3),
          title: 'Amazing Grace',
        ),
        SplitMarker(
          id: 'marker-0',
          position: Duration.zero,
          title: 'Opening Song',
        ),
      ],
      fadeDuration: const Duration(milliseconds: 250),
      appliedAt: DateTime.utc(2026, 6, 15, 10),
    );

    expect(result.plan.markers.map((marker) => marker.title), [
      'Opening Song',
      'Amazing Grace',
      'Blessed Assurance',
    ]);
    expect(result.plan.hasFade, isTrue);
    expect(result.children, hasLength(3));
    expect(result.children.first.kind, DownloadItemKind.manualSegment);
    expect(result.children.first.title, 'Opening Song');
    expect(result.children.first.startTime, Duration.zero);
    expect(result.children.first.endTime, const Duration(minutes: 3));
    expect(result.children.first.sourceFilePath, '/tmp/source.mp3');
    expect(
      result.children.first.fadeDuration,
      const Duration(milliseconds: 250),
    );
    expect(result.children.last.title, 'Blessed Assurance');
    expect(result.children.last.startTime, const Duration(minutes: 7));
    expect(result.children.last.endTime, const Duration(minutes: 12));
  });

  test('adds default zero marker when first marker starts later', () {
    final result = const SplitPlanBuilder().build(
      sourceFilePath: '/tmp/source.mp3',
      duration: const Duration(minutes: 10),
      markers: const [
        SplitMarker(
          id: 'marker-1',
          position: Duration(minutes: 4),
          title: 'Second Song',
        ),
      ],
      fadeDuration: Duration.zero,
      appliedAt: DateTime.utc(2026, 6, 15, 10),
    );

    expect(result.plan.markers.first.position, Duration.zero);
    expect(result.children.first.title, 'Track 01');
    expect(result.children.first.endTime, const Duration(minutes: 4));
    expect(result.children.last.title, 'Second Song');
  });

  test('falls back to numbered title when marker title is empty', () {
    final result = const SplitPlanBuilder().build(
      sourceFilePath: '/tmp/source.mp3',
      duration: const Duration(minutes: 10),
      markers: const [
        SplitMarker(id: 'marker-0', position: Duration.zero, title: ''),
      ],
      fadeDuration: Duration.zero,
      appliedAt: DateTime.utc(2026, 6, 15, 10),
    );

    expect(result.children.single.title, 'Track 01');
  });

  test('rejects markers that are too close together', () {
    expect(
      () => const SplitPlanBuilder().build(
        sourceFilePath: '/tmp/source.mp3',
        duration: const Duration(minutes: 10),
        markers: const [
          SplitMarker(id: 'marker-0', position: Duration.zero, title: 'First'),
          SplitMarker(
            id: 'marker-1',
            position: Duration(seconds: 1),
            title: 'Too Close',
          ),
        ],
        fadeDuration: Duration.zero,
        appliedAt: DateTime.utc(2026, 6, 15, 10),
      ),
      throwsA(isA<SplitPlanException>()),
    );
  });

  test('ignores markers outside the track duration', () {
    final result = const SplitPlanBuilder().build(
      sourceFilePath: '/tmp/source.mp3',
      duration: const Duration(minutes: 5),
      markers: const [
        SplitMarker(id: 'marker-0', position: Duration.zero, title: 'Only'),
        SplitMarker(
          id: 'marker-end',
          position: Duration(minutes: 5),
          title: 'At End',
        ),
        SplitMarker(
          id: 'marker-after',
          position: Duration(minutes: 6),
          title: 'After End',
        ),
      ],
      fadeDuration: Duration.zero,
      appliedAt: DateTime.utc(2026, 6, 15, 10),
    );

    expect(result.plan.markers, hasLength(1));
    expect(result.children.single.endTime, const Duration(minutes: 5));
  });
}

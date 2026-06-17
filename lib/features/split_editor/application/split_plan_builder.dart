import '../../../models/download_models.dart';

class SplitPlanBuildResult {
  const SplitPlanBuildResult({required this.plan, required this.children});

  final SplitPlan plan;
  final List<DownloadItem> children;
}

class SplitPlanBuilder {
  const SplitPlanBuilder();

  static const minimumMarkerSpacing = Duration(seconds: 2);

  SplitPlanBuildResult build({
    required String sourceFilePath,
    required Duration duration,
    required List<SplitMarker> markers,
    required Duration fadeDuration,
    required DateTime appliedAt,
  }) {
    if (sourceFilePath.trim().isEmpty) {
      throw const SplitPlanException('Source file path is empty.');
    }
    if (duration <= Duration.zero) {
      throw const SplitPlanException(
        'Track duration must be greater than zero.',
      );
    }

    final normalizedMarkers = _normalizeMarkers(markers, duration);
    final children = <DownloadItem>[];
    for (var index = 0; index < normalizedMarkers.length; index += 1) {
      final marker = normalizedMarkers[index];
      final nextMarker = index + 1 < normalizedMarkers.length
          ? normalizedMarkers[index + 1]
          : null;
      final endTime = nextMarker?.position ?? duration;
      final title = _segmentTitle(marker.title, index);

      children.add(
        DownloadItem(
          id: 'segment:${index + 1}',
          kind: DownloadItemKind.manualSegment,
          title: title,
          sourceFilePath: sourceFilePath,
          duration: endTime - marker.position,
          startTime: marker.position,
          endTime: endTime,
          fadeDuration: fadeDuration,
          status: DownloadStatus.ready,
          progress: 0,
        ),
      );
    }

    return SplitPlanBuildResult(
      plan: SplitPlan(
        sourceFilePath: sourceFilePath,
        markers: normalizedMarkers,
        fadeDuration: fadeDuration,
        appliedAt: appliedAt,
      ),
      children: children,
    );
  }

  List<SplitMarker> _normalizeMarkers(
    List<SplitMarker> markers,
    Duration duration,
  ) {
    final usableMarkers =
        markers
            .where((marker) => marker.position >= Duration.zero)
            .where((marker) => marker.position < duration)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));

    final hasZeroMarker = usableMarkers.any(
      (marker) => marker.position == Duration.zero,
    );
    if (!hasZeroMarker) {
      usableMarkers.insert(
        0,
        const SplitMarker(
          id: 'marker:0',
          position: Duration.zero,
          title: 'Track 01',
        ),
      );
    }

    final normalized = <SplitMarker>[];
    for (final marker in usableMarkers) {
      if (normalized.isNotEmpty &&
          marker.position - normalized.last.position < minimumMarkerSpacing) {
        throw SplitPlanException(
          'Markers must be at least ${minimumMarkerSpacing.inSeconds} seconds apart.',
        );
      }
      normalized.add(marker);
    }

    return normalized;
  }

  String _segmentTitle(String title, int index) {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return 'Track ${(index + 1).toString().padLeft(2, '0')}';
  }
}

class SplitPlanException implements Exception {
  const SplitPlanException(this.message);

  final String message;

  @override
  String toString() => message;
}

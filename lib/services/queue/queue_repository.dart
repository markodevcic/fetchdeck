import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/download_models.dart';

class QueueRepository {
  const QueueRepository();

  static const _fileName = 'queue.json';

  Future<List<DownloadJob>> load() async {
    final file = await _queueFile();
    if (!await file.exists()) return const [];

    try {
      final payload = jsonDecode(await file.readAsString());
      if (payload is! List) return const [];

      return payload
          .whereType<Map>()
          .map((item) => DownloadJob.fromJson(Map<String, dynamic>.from(item)))
          .whereType<DownloadJob>()
          .map(_normalizeRestoredJob)
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> save(List<DownloadJob> jobs) async {
    final file = await _queueFile();
    await file.parent.create(recursive: true);

    final tempFile = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await tempFile.writeAsString(
      encoder.convert(jobs.map((job) => job.toJson()).toList()),
      flush: true,
    );

    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  Future<File> _queueFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  DownloadJob _normalizeRestoredJob(DownloadJob job) {
    return switch (job.status) {
      DownloadStatus.downloading => job.copyWith(
        status: DownloadStatus.ready,
        progress: 0,
        eta: 'Interrupted',
        error: null,
      ),
      DownloadStatus.analyzing => job.copyWith(
        status: DownloadStatus.failed,
        progress: 0,
        eta: 'Analysis interrupted',
        error: 'Analysis was interrupted when the app closed.',
      ),
      _ => job,
    };
  }
}

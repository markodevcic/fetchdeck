import 'dart:io';

import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fileSelectionServiceProvider = Provider<FileSelectionService>(
  (ref) => const FileSelectionService(),
);

class FileSelectionService {
  const FileSelectionService();

  Future<String?> pickOutputDirectory({String? initialDirectory}) {
    return file_picker.FilePicker.getDirectoryPath(
      dialogTitle: 'Choose output folder',
      initialDirectory: initialDirectory,
    );
  }

  Future<String?> pickToolPath({
    required String toolLabel,
    required String? currentPath,
  }) async {
    final result = await file_picker.FilePicker.pickFiles(
      dialogTitle: 'Choose $toolLabel',
      initialDirectory: parentDirectory(currentPath),
    );
    final files = result?.files;
    return files == null || files.isEmpty ? null : files.first.path;
  }

  String? parentDirectory(String? path) {
    if (path == null) return null;
    return File(path).parent.path;
  }
}

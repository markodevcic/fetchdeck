import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final fileActionsServiceProvider = Provider<FileActionsService>(
  (ref) => const FileActionsService(),
);

class FileActionsService {
  const FileActionsService();

  Future<void> open(String path) async {
    final entityType = await FileSystemEntity.type(path);
    if (entityType == FileSystemEntityType.notFound) {
      throw FileActionException('Path does not exist: $path');
    }

    if (Platform.isMacOS) {
      await _run('open', [path]);
      return;
    }

    if (Platform.isWindows) {
      await _run('cmd', ['/c', 'start', '', path]);
      return;
    }

    if (Platform.isLinux) {
      await _run('xdg-open', [path]);
      return;
    }

    throw const FileActionException('Opening files is not supported here.');
  }

  Future<void> reveal(String path) async {
    final entityType = await FileSystemEntity.type(path);
    if (entityType == FileSystemEntityType.notFound) {
      throw FileActionException('Path does not exist: $path');
    }

    if (Platform.isMacOS) {
      await _run(
        'open',
        entityType == FileSystemEntityType.directory ? [path] : ['-R', path],
      );
      return;
    }

    if (Platform.isWindows) {
      await _run(
        'explorer.exe',
        entityType == FileSystemEntityType.directory
            ? [path]
            : ['/select,$path'],
      );
      return;
    }

    if (Platform.isLinux) {
      final targetPath = entityType == FileSystemEntityType.directory
          ? path
          : File(path).parent.path;
      await _run('xdg-open', [targetPath]);
      return;
    }

    throw const FileActionException('Opening folders is not supported here.');
  }

  Future<void> openFullDiskAccessSettings() async {
    if (Platform.isMacOS) {
      await _run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
      ]);
      return;
    }

    throw const FileActionException(
      'Opening Full Disk Access settings is only supported on macOS.',
    );
  }

  Future<void> _run(String executable, List<String> arguments) async {
    final result = await Process.run(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );

    if (result.exitCode != 0) {
      final message = result.stderr.toString().trim();
      throw FileActionException(
        message.isEmpty ? 'Could not open output folder.' : message,
      );
    }
  }
}

class FileActionException implements Exception {
  const FileActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

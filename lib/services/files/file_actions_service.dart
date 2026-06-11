import 'dart:io';

class FileActionsService {
  const FileActionsService();

  Future<void> reveal(String path) async {
    final entityType = await FileSystemEntity.type(path);
    if (entityType == FileSystemEntityType.notFound) {
      throw FileActionException('Path does not exist: $path');
    }

    final targetPath = entityType == FileSystemEntityType.directory
        ? path
        : File(path).parent.path;

    if (Platform.isMacOS) {
      await _run('open', [targetPath]);
      return;
    }

    if (Platform.isWindows) {
      await _run('explorer.exe', [targetPath]);
      return;
    }

    if (Platform.isLinux) {
      await _run('xdg-open', [targetPath]);
      return;
    }

    throw const FileActionException('Opening folders is not supported here.');
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/services/tools/tool_discovery.dart';

void main() {
  test(
    'bundled tool reports executable version before manifest version',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fetchdeck_tool_',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final tool = File('${directory.path}/yt-dlp');
      await tool.writeAsString('#!/bin/sh\necho 2026.06.09\n');
      await Process.run('chmod', ['+x', tool.path]);

      final info = await ToolDiscovery().findTool(
        executableNames: const ['missing-tool'],
        bundledPath: tool.path,
        bundledVersion: '2026.03.17',
        fallbackPaths: const [],
        versionArguments: const ['--version'],
      );

      expect(info.isAvailable, isTrue);
      expect(info.source, ToolSource.bundled);
      expect(info.version, '2026.06.09');
    },
  );
}

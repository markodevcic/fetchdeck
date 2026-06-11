import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/download_models.dart';

class CustomPresetRepository {
  const CustomPresetRepository();

  static const _fileName = 'custom_presets.json';

  Future<List<PresetDefinition>> load() async {
    final file = await _presetFile();
    if (!await file.exists()) return const [];

    try {
      final payload = jsonDecode(await file.readAsString());
      if (payload is! List) return const [];

      return payload
          .whereType<Map>()
          .map(
            (item) =>
                PresetDefinition.fromJson(Map<String, dynamic>.from(item)),
          )
          .whereType<PresetDefinition>()
          .where((preset) => !preset.isBuiltIn)
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> save(List<PresetDefinition> presets) async {
    final customPresets = presets
        .where((preset) => !preset.isBuiltIn)
        .toList(growable: false);
    final file = await _presetFile();
    await file.parent.create(recursive: true);

    final tempFile = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await tempFile.writeAsString(
      encoder.convert(customPresets.map((preset) => preset.toJson()).toList()),
      flush: true,
    );

    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  Future<File> _presetFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}

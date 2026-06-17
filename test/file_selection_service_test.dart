import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/services/files/file_selection_service.dart';

void main() {
  test('parentDirectory returns containing folder for a selected file', () {
    const service = FileSelectionService();

    expect(service.parentDirectory('/tmp/tools/yt-dlp'), '/tmp/tools');
    expect(service.parentDirectory(null), isNull);
  });
}

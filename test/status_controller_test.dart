import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/shell/application/status_controller.dart';

void main() {
  test('status controller exposes initial message and updates it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(statusControllerProvider), initialStatusMessage);

    container
        .read(statusControllerProvider.notifier)
        .setMessage('Download complete.');

    expect(container.read(statusControllerProvider), 'Download complete.');
    expect(
      container.read(activityControllerProvider).entries.first.message,
      'Download complete.',
    );
  });

  test('activity controller keeps the latest bounded entries', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    for (var index = 0; index < maxActivityEntries + 10; index += 1) {
      container
          .read(statusControllerProvider.notifier)
          .setMessage('Activity $index');
    }

    final entries = container.read(activityControllerProvider).entries;
    expect(entries, hasLength(maxActivityEntries));
    expect(entries.first.message, 'Activity ${maxActivityEntries + 9}');
    expect(entries.last.message, 'Activity 10');
  });
}

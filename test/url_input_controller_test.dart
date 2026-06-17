import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/downloads/application/url_input_controller.dart';

void main() {
  test('looksLikeUrl accepts http and https URLs only', () {
    expect(
      UrlInputController.looksLikeUrl('https://youtube.com/watch?v=1'),
      isTrue,
    );
    expect(UrlInputController.looksLikeUrl('http://example.com/video'), isTrue);
    expect(UrlInputController.looksLikeUrl('ftp://example.com/video'), isFalse);
    expect(UrlInputController.looksLikeUrl('not a url'), isFalse);
  });

  test('handleChanged schedules analysis only for pasted URLs', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(urlInputControllerProvider.notifier);

    expect(
      controller.handleChanged('https://', isAnalyzing: false),
      UrlInputAction.none,
    );
    expect(
      controller.handleChanged(
        'https://youtube.com/watch?v=abc123',
        isAnalyzing: false,
      ),
      UrlInputAction.scheduleAnalyze,
    );
  });

  test('handleChanged ignores changes while analysis is running', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(urlInputControllerProvider.notifier);

    expect(
      controller.handleChanged(
        'https://youtube.com/watch?v=abc123',
        isAnalyzing: true,
      ),
      UrlInputAction.none,
    );
  });

  test('programmatic text and clear update tracked text', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(urlInputControllerProvider.notifier);

    controller.setProgrammaticText(' https://example.com ');
    expect(
      container.read(urlInputControllerProvider).lastText,
      'https://example.com',
    );

    controller.clear();
    expect(container.read(urlInputControllerProvider).lastText, '');
  });
}

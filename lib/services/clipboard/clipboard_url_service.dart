import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/downloads/application/url_input_controller.dart';

final clipboardUrlServiceProvider = Provider<ClipboardUrlService>(
  (ref) => const ClipboardUrlService(),
);

class ClipboardUrlService {
  const ClipboardUrlService();

  Future<String> readUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    return UrlInputController.looksLikeUrl(text) ? text : '';
  }
}

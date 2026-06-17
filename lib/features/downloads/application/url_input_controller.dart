import 'package:flutter_riverpod/flutter_riverpod.dart';

final urlInputControllerProvider =
    NotifierProvider<UrlInputController, UrlInputState>(UrlInputController.new);

enum UrlInputAction { none, scheduleAnalyze }

class UrlInputState {
  const UrlInputState({this.lastText = ''});

  final String lastText;
}

class UrlInputController extends Notifier<UrlInputState> {
  @override
  UrlInputState build() => const UrlInputState();

  UrlInputAction handleChanged(String value, {required bool isAnalyzing}) {
    final current = value.trim();
    final previous = state.lastText;
    state = UrlInputState(lastText: current);

    if (current.isEmpty || isAnalyzing) return UrlInputAction.none;

    final looksLikePaste = current.length - previous.length > 8;
    if (!looksLikePaste || !looksLikeUrl(current)) {
      return UrlInputAction.none;
    }

    return UrlInputAction.scheduleAnalyze;
  }

  void setProgrammaticText(String value) {
    state = UrlInputState(lastText: value.trim());
  }

  void clear() {
    state = const UrlInputState();
  }

  static bool looksLikeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}

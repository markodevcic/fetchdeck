import 'package:flutter_riverpod/flutter_riverpod.dart';

final navigationControllerProvider =
    NotifierProvider<NavigationController, String>(NavigationController.new);

class NavigationController extends Notifier<String> {
  @override
  String build() => 'Downloads';

  void select(String section) {
    state = section;
  }
}

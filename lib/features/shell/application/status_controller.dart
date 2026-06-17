import 'package:flutter_riverpod/flutter_riverpod.dart';

const initialStatusMessage = 'Checking yt-dlp, ffmpeg, and ffprobe...';
const maxActivityEntries = 500;

final statusControllerProvider = NotifierProvider<StatusController, String>(
  StatusController.new,
);

final activityControllerProvider =
    NotifierProvider<ActivityController, ActivityState>(ActivityController.new);

class ActivityState {
  const ActivityState({this.entries = const []});

  final List<ActivityEntry> entries;
}

class ActivityEntry {
  const ActivityEntry({required this.message, required this.createdAt});

  final String message;
  final DateTime createdAt;
}

class StatusController extends Notifier<String> {
  @override
  String build() => initialStatusMessage;

  void setMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    state = trimmed;
    ref.read(activityControllerProvider.notifier).add(trimmed);
  }
}

class ActivityController extends Notifier<ActivityState> {
  @override
  ActivityState build() {
    return ActivityState(
      entries: [
        ActivityEntry(message: initialStatusMessage, createdAt: DateTime.now()),
      ],
    );
  }

  void add(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    final entries = [
      ActivityEntry(message: trimmed, createdAt: DateTime.now()),
      ...state.entries,
    ];
    state = ActivityState(
      entries: entries.length <= maxActivityEntries
          ? entries
          : entries.take(maxActivityEntries).toList(growable: false),
    );
  }
}

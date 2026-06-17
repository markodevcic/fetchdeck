import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as forui;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';

import '../application/status_controller.dart';

class StatusBar extends StatefulWidget {
  const StatusBar({super.key, required this.message, required this.activities});

  final String message;
  final List<ActivityEntry> activities;

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
  late final forui.FAccordionController controller;

  @override
  void initState() {
    super.initState();
    controller = forui.FAccordionController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      color: theme.colorScheme.background,
      child: forui.FAccordion(
        control: forui.FAccordionControl.managed(controller: controller),
        children: [
          forui.FAccordionItem(
            title: _ActivityHeader(message: widget.message),
            child: SizedBox(
              height: 180,
              child: _ActivityList(activities: widget.activities),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Row(
      children: [
        Icon(
          LucideIcons.terminal,
          size: 15,
          color: theme.colorScheme.mutedForeground,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.muted,
          ),
        ),
      ],
    );
  }
}

class _ActivityList extends StatefulWidget {
  const _ActivityList({required this.activities});

  final List<ActivityEntry> activities;

  @override
  State<_ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends State<_ActivityList> {
  final verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToBottomAfterLayout();
  }

  @override
  void didUpdateWidget(covariant _ActivityList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activities.length != widget.activities.length ||
        oldWidget.activities.lastOrNull?.message !=
            widget.activities.lastOrNull?.message) {
      _scrollToBottomAfterLayout();
    }
  }

  @override
  void dispose() {
    verticalScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !verticalScrollController.hasClients) return;
      verticalScrollController.jumpTo(
        verticalScrollController.position.maxScrollExtent,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    if (widget.activities.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Text('No activity yet.', style: theme.textTheme.muted),
        ),
      );
    }

    final activities = _orderedActivities(widget.activities);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.muted.withValues(alpha: 0.22),
          border: Border.all(color: theme.colorScheme.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListView.separated(
          controller: verticalScrollController,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          itemCount: activities.length,
          separatorBuilder: (_, _) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            return _ActivityRow(entry: activities[index]);
          },
        ),
      ),
    );
  }

  List<ActivityEntry> _orderedActivities(List<ActivityEntry> entries) {
    return [...entries]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.background.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              _formatActivityTime(entry.createdAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 18, color: theme.colorScheme.border),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatActivityTime(DateTime value) {
  final dateLabel = _formatDate(value);
  final timeLabel = _formatTime(value);
  return '$dateLabel $timeLabel';
}

String _formatDate(DateTime value) {
  final now = DateTime.now();
  final local = value.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  if (date == today) return 'Today';
  if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

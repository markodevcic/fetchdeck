import 'dart:io';

import 'package:forui/forui.dart' as forui;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';

import '../../../models/download_models.dart';
import '../../../shared/presentation/spinning_icon.dart';
import '../application/queue_controller.dart';

typedef ChildSelectionChanged =
    void Function({
      required DownloadJob job,
      required DownloadItem child,
      required bool isSelected,
    });

typedef ChildSelectAllChanged =
    void Function({required DownloadJob job, required bool isSelected});

class QueuePanel extends StatelessWidget {
  const QueuePanel({
    super.key,
    required this.title,
    required this.jobs,
    required this.selectedJobId,
    required this.hasOutputDirectory,
    required this.canStartAll,
    required this.statusFilter,
    required this.searchQuery,
    required this.onSelected,
    required this.onStart,
    required this.onCancel,
    required this.onSplit,
    required this.onReveal,
    required this.onRemove,
    required this.onStartAll,
    required this.onStatusFilterChanged,
    required this.onSearchChanged,
    required this.onToggleExpanded,
    required this.onChildSelected,
    required this.onSelectAllChildren,
  });

  final String title;
  final List<DownloadJob> jobs;
  final String? selectedJobId;
  final bool hasOutputDirectory;
  final bool canStartAll;
  final QueueStatusFilter statusFilter;
  final String searchQuery;
  final ValueChanged<DownloadJob> onSelected;
  final ValueChanged<DownloadJob> onStart;
  final ValueChanged<DownloadJob> onCancel;
  final ValueChanged<DownloadJob> onSplit;
  final ValueChanged<DownloadJob> onReveal;
  final ValueChanged<DownloadJob> onRemove;
  final VoidCallback onStartAll;
  final ValueChanged<QueueStatusFilter> onStatusFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<DownloadJob> onToggleExpanded;
  final ChildSelectionChanged onChildSelected;
  final ChildSelectAllChanged onSelectAllChildren;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final emptyState = _emptyStateFor(statusFilter, searchQuery);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 38,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text(title, style: theme.textTheme.h4)),
              SizedBox(width: 180, child: _buildHeaderAction()),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _QueueFilters(
          statusFilter: statusFilter,
          searchQuery: searchQuery,
          showSearch: jobs.isNotEmpty || searchQuery.trim().isNotEmpty,
          onStatusFilterChanged: onStatusFilterChanged,
          onSearchChanged: onSearchChanged,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: jobs.isEmpty
              ? _EmptyQueue(
                  title: emptyState.title,
                  description: emptyState.description,
                )
              : ListView.separated(
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return _JobRow(
                      job: job,
                      selected: selectedJobId == job.id,
                      onPressed: () => onSelected(job),
                      onStart: () => onStart(job),
                      onCancel: () => onCancel(job),
                      onSplit: () => onSplit(job),
                      onReveal: () => onReveal(job),
                      onRemove: () => onRemove(job),
                      onToggleExpanded: () => onToggleExpanded(job),
                      onChildSelected: (child, isSelected) => onChildSelected(
                        job: job,
                        child: child,
                        isSelected: isSelected,
                      ),
                      onSelectAllChildren: (isSelected) =>
                          onSelectAllChildren(job: job, isSelected: isSelected),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHeaderAction() {
    return forui.FButton(
      variant: forui.FButtonVariant.outline,
      size: forui.FButtonSizeVariant.sm,
      style: const forui.FButtonStyleDelta.delta(
        contentStyle: forui.FButtonContentStyleDelta.delta(
          padding: forui.EdgeInsetsGeometryDelta.value(
            EdgeInsets.symmetric(horizontal: 7, vertical: 9),
          ),
        ),
      ),
      mainAxisSize: MainAxisSize.min,
      onPress: !canStartAll || !hasOutputDirectory ? null : onStartAll,
      prefix: const Icon(LucideIcons.play, size: 15),
      child: const Text('Start All'),
    );
  }
}

({String title, String description}) _emptyStateFor(
  QueueStatusFilter filter,
  String searchQuery,
) {
  final query = searchQuery.trim();
  if (query.isNotEmpty) {
    return (
      title: 'No matches',
      description:
          'No ${filter.label.toLowerCase()} downloads match "$query". Try a different title, source, URL, or preset.',
    );
  }

  return switch (filter) {
    QueueStatusFilter.all => (
      title: 'No downloads yet',
      description:
          'Paste a video, playlist, channel, or batch URL above to analyze it and add it here.',
    ),
    QueueStatusFilter.ready => (
      title: 'Nothing ready to start',
      description:
          'Analyzed jobs that are ready to download will appear here. Paste a URL above to create one.',
    ),
    QueueStatusFilter.downloading => (
      title: 'No active downloads',
      description:
          'Downloads that are currently queued or running will appear here while Fetchdeck is working.',
    ),
    QueueStatusFilter.failed => (
      title: 'No failed downloads',
      description:
          'Jobs that need attention will appear here with retry actions and error details.',
    ),
    QueueStatusFilter.complete => (
      title: 'No completed downloads',
      description:
          'Finished jobs will appear here with reveal, redownload, and history actions.',
    ),
  };
}

class _QueueFilters extends StatefulWidget {
  const _QueueFilters({
    required this.statusFilter,
    required this.searchQuery,
    required this.showSearch,
    required this.onStatusFilterChanged,
    required this.onSearchChanged,
  });

  final QueueStatusFilter statusFilter;
  final String searchQuery;
  final bool showSearch;
  final ValueChanged<QueueStatusFilter> onStatusFilterChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  State<_QueueFilters> createState() => _QueueFiltersState();
}

class _QueueFiltersState extends State<_QueueFilters> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant _QueueFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != controller.text) {
      controller.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final statusFilters = _QueueFilterTabs(
          value: widget.statusFilter,
          onChanged: widget.onStatusFilterChanged,
        );
        final search = SizedBox(
          width: compact ? double.infinity : 220,
          child: forui.FTextField(
            control: forui.FTextFieldControl.managed(
              controller: controller,
              onChange: (value) => widget.onSearchChanged(value.text),
            ),
            hint: 'Search queue',
            prefixBuilder: (_, _, _) => const Padding(
              padding: EdgeInsetsDirectional.only(start: 12, end: 4),
              child: Icon(LucideIcons.search, size: 15),
            ),
            onSubmit: widget.onSearchChanged,
            clearable: (value) => value.text.isNotEmpty,
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              statusFilters,
              if (widget.showSearch) ...[const SizedBox(height: 10), search],
            ],
          );
        }

        return Row(
          children: [
            Align(alignment: Alignment.centerLeft, child: statusFilters),
            if (widget.showSearch) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: search),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _QueueFilterTabs extends StatelessWidget {
  const _QueueFilterTabs({required this.value, required this.onChanged});

  final QueueStatusFilter value;
  final ValueChanged<QueueStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final filters = QueueStatusFilter.values;
    final selectedIndex = filters.indexOf(value).clamp(0, filters.length - 1);

    return IntrinsicWidth(
      child: SizedBox(
        height: 38,
        child: forui.FTabs(
          scrollable: true,
          physics: const NeverScrollableScrollPhysics(),
          control: forui.FTabControl.lifted(
            index: selectedIndex,
            onChange: (index) => onChanged(filters[index]),
          ),
          style: forui.FTabsStyleDelta.delta(
            spacing: 0,
            height: 28,
            labelTextStyle: forui.FVariantsDelta.delta([
              forui.FVariantOperation.base(
                forui.TextStyleDelta.value(
                  theme.textTheme.small.copyWith(
                    color: theme.colorScheme.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              forui.FVariantOperation.exact(
                {forui.FTabVariant.selected},
                forui.TextStyleDelta.value(
                  theme.textTheme.small.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          indicatorDecoration: forui.DecorationDelta.value(
            ShapeDecoration(
              color: Colors.white,
              shape: RoundedSuperellipseBorder(borderRadius: theme.radius),
            ),
          ),
          ),
          children: [
            for (final filter in filters)
              forui.FTabEntry(
                label: Text(filter.label, maxLines: 1, softWrap: false),
                child: const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.clipboardList,
              size: 34,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.large),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    required this.job,
    required this.selected,
    required this.onPressed,
    required this.onStart,
    required this.onCancel,
    required this.onSplit,
    required this.onReveal,
    required this.onRemove,
    required this.onToggleExpanded,
    required this.onChildSelected,
    required this.onSelectAllChildren,
  });

  final DownloadJob job;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onSplit;
  final VoidCallback onReveal;
  final VoidCallback onRemove;
  final VoidCallback onToggleExpanded;
  final void Function(DownloadItem child, bool isSelected) onChildSelected;
  final ValueChanged<bool> onSelectAllChildren;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final sourceLabel = _sourceLabel(job);
    const cardHeight = 140.0;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            splashFactory: NoSplash.splashFactory,
            onTap: onPressed,
            child: SizedBox(
              height: cardHeight,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.accent.withValues(alpha: 0.45)
                      : null,
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.ring
                        : theme.colorScheme.border,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Thumbnail(info: job.mediaInfo),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      job.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.small.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$sourceLabel • ${job.preset.label}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.muted,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (job.hasChildren)
                                _ChildCountButton(
                                  job: job,
                                  onPressed: onToggleExpanded,
                                ),
                            ],
                          ),
                          const Spacer(),
                          _JobFooter(
                            job: job,
                            onStart: onStart,
                            onCancel: onCancel,
                            onSplit: onSplit,
                            onReveal: onReveal,
                            onRemove: onRemove,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (job.hasChildren)
          _ExpandableChildItems(
            expanded: job.isExpanded,
            child: _ChildItemList(
              job: job,
              onChildSelected: onChildSelected,
              onSelectAllChildren: onSelectAllChildren,
            ),
          ),
      ],
    );
  }
}

class _ExpandableChildItems extends StatelessWidget {
  const _ExpandableChildItems({required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.topCenter,
        heightFactor: expanded ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutQuart,
        child: IgnorePointer(ignoring: !expanded, child: child),
      ),
    );
  }
}

class _ChildCountButton extends StatelessWidget {
  const _ChildCountButton({required this.job, required this.onPressed});

  final DownloadJob job;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    return _IconTooltip(
      message: job.isExpanded ? 'Hide tracks' : 'Show tracks',
      child: forui.FButton(
        variant: forui.FButtonVariant.ghost,
        size: forui.FButtonSizeVariant.sm,
        mainAxisSize: MainAxisSize.min,
        onPress: onPressed,
        prefix: AnimatedRotation(
          turns: job.isExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: const Icon(LucideIcons.chevronDown, size: 15),
        ),
        child: Text(
          '${job.selectedChildCount}/${job.childCount}',
          style: theme.textTheme.small,
        ),
      ),
    );
  }
}

class _IconTooltip extends StatelessWidget {
  const _IconTooltip({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return forui.FTooltip(
      style: const forui.FTooltipStyleDelta.delta(
        hoverEnterDuration: Duration(seconds: 1),
      ),
      tipBuilder: (context, _) => Text(message),
      child: child,
    );
  }
}

class _ChildItemList extends StatelessWidget {
  const _ChildItemList({
    required this.job,
    required this.onChildSelected,
    required this.onSelectAllChildren,
  });

  final DownloadJob job;
  final void Function(DownloadItem child, bool isSelected) onChildSelected;
  final ValueChanged<bool> onSelectAllChildren;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final allSelected = job.children.every((child) => child.isSelected);
    final selectionLocked = job.children.any(
      (child) => _locksChildSelection(child.status),
    );

    return Container(
      margin: const EdgeInsets.only(top: 6, left: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.28),
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    job.children.first.kind == DownloadItemKind.chapter
                        ? LucideIcons.listMusic
                        : LucideIcons.listVideo,
                    size: 15,
                    color: theme.colorScheme.mutedForeground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${job.selectedChildCount} of ${job.childCount} selected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                  if (selectionLocked)
                    Text(
                      'Selection locked',
                      style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.mutedForeground,
                      ),
                    )
                  else
                    forui.FButton(
                      variant: forui.FButtonVariant.ghost,
                      size: forui.FButtonSizeVariant.sm,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () => onSelectAllChildren(!allSelected),
                      child: Text(allSelected ? 'None' : 'All'),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.border),
          for (final child in job.children)
            _ChildItemRow(
              item: child,
              selectionLocked: selectionLocked,
              onChanged: (isSelected) => onChildSelected(child, isSelected),
            ),
        ],
      ),
    );
  }
}

class _ChildItemRow extends StatelessWidget {
  const _ChildItemRow({
    required this.item,
    required this.selectionLocked,
    required this.onChanged,
  });

  final DownloadItem item;
  final bool selectionLocked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final detail = _childDetailLabel(item);
    final isActive = item.status == DownloadStatus.downloading;

    final hasProgress =
        item.status == DownloadStatus.queued ||
        item.status == DownloadStatus.downloading;
    final showError =
        item.status == DownloadStatus.failed && item.error != null;

    return SizedBox(
      height: 66,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        onTap: selectionLocked ? null : () => onChanged(!item.isSelected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 17,
                child: selectionLocked
                    ? null
                    : Icon(
                        item.isSelected
                            ? LucideIcons.squareCheckBig
                            : LucideIcons.square,
                        size: 17,
                        color: item.isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.mutedForeground,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.small.copyWith(
                        fontWeight: isActive
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: item.isSelected
                            ? theme.colorScheme.foreground
                            : theme.colorScheme.mutedForeground,
                      ),
                    ),
                    if (showError)
                      Text(
                        item.error!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.muted.copyWith(
                          color: const Color(0xFFB91C1C),
                        ),
                      )
                    else if (detail != null)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.muted,
                      ),
                    const SizedBox(height: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Opacity(
                        opacity: hasProgress ? 1 : 0,
                        child: _AnimatedProgress(value: item.progress),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _ChildStatusBadge(item: item, label: _childStatusLabel(item)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildStatusBadge extends StatelessWidget {
  const _ChildStatusBadge({required this.item, this.label});

  final DownloadItem item;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final color = _childStatusColor(item);

    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.42)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ChildStatusIcon(item: item, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label ?? item.status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.small.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobFooter extends StatelessWidget {
  const _JobFooter({
    required this.job,
    required this.onStart,
    required this.onCancel,
    required this.onSplit,
    required this.onReveal,
    required this.onRemove,
  });

  final DownloadJob job;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onSplit;
  final VoidCallback onReveal;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final statusLine = _jobStatusLine(job);
    final canRevealOutput =
        job.status == DownloadStatus.complete &&
        _pathExists(job.bestOutputPath);
    final canOpenSplitEditor = _pathExists(job.splitEditorSourcePath);
    final canRemove = job.status != DownloadStatus.downloading;
    final action = _primaryActionFor(
      job,
      canExportManualSegments: canOpenSplitEditor,
    );
    final actionColor = action.color;

    return SizedBox(
      height: 66,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const actionWidth = 176.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.small.copyWith(
                  color: _statusTextColor(theme, job.status),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: _AnimatedProgress(value: job.progress),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: actionWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _IconTooltip(
                          message: action.label,
                          child: _ForuiIconActionButton(
                            icon: action.icon,
                            tooltipLabel: action.label,
                            backgroundColor: actionColor,
                            foregroundColor: Colors.white,
                            isSpinner: action.isSpinner,
                            onPressed: action.isDisabled
                                ? null
                                : action.isCancel
                                ? onCancel
                                : onStart,
                          ),
                        ),
                        const SizedBox(width: 2),
                        _IconTooltip(
                          message: 'Show in folder',
                          child: _ForuiIconActionButton.ghost(
                            icon: LucideIcons.folderOpen,
                            tooltipLabel: 'Show in folder',
                            enabled: canRevealOutput,
                            disabledColor: theme.colorScheme.mutedForeground
                                .withValues(alpha: 0.36),
                            onPressed: canRevealOutput ? onReveal : null,
                          ),
                        ),
                        const SizedBox(width: 2),
                        _IconTooltip(
                          message: 'Split track',
                          child: _ForuiIconActionButton.ghost(
                            icon: LucideIcons.scissors,
                            tooltipLabel: 'Split track',
                            enabled: canOpenSplitEditor,
                            disabledColor: theme.colorScheme.mutedForeground
                                .withValues(alpha: 0.36),
                            onPressed: canOpenSplitEditor ? onSplit : null,
                          ),
                        ),
                        const SizedBox(width: 2),
                        _IconTooltip(
                          message: 'Remove',
                          child: _ForuiIconActionButton.ghost(
                            icon: LucideIcons.trash2,
                            tooltipLabel: 'Remove',
                            foregroundColor: _JobActionColors.delete,
                            hoverBackgroundColor: _JobActionColors.delete
                                .withValues(alpha: 0.14),
                            pressedBackgroundColor: _JobActionColors.delete
                                .withValues(alpha: 0.22),
                            enabled: canRemove,
                            onPressed: canRemove ? onRemove : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ForuiIconActionButton extends StatelessWidget {
  const _ForuiIconActionButton({
    required this.icon,
    required this.tooltipLabel,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.isSpinner = false,
  }) : enabled = true,
       hoverBackgroundColor = null,
       pressedBackgroundColor = null,
       disabledColor = null;

  const _ForuiIconActionButton.ghost({
    required this.icon,
    required this.tooltipLabel,
    required this.onPressed,
    this.enabled = true,
    this.foregroundColor,
    this.disabledColor,
    this.hoverBackgroundColor,
    this.pressedBackgroundColor,
  }) : backgroundColor = Colors.transparent,
       isSpinner = false;

  final IconData icon;
  final String tooltipLabel;
  final Color backgroundColor;
  final Color? foregroundColor;
  final Color? hoverBackgroundColor;
  final Color? pressedBackgroundColor;
  final Color? disabledColor;
  final bool enabled;
  final bool isSpinner;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final effectiveForeground = enabled
        ? foregroundColor ?? theme.colorScheme.foreground
        : disabledColor ??
              theme.colorScheme.mutedForeground.withValues(alpha: 0.36);
    final effectiveBackground = enabled
        ? backgroundColor
        : backgroundColor == Colors.transparent
        ? Colors.transparent
        : backgroundColor.withValues(alpha: 0.38);
    final customBackground =
        backgroundColor != Colors.transparent ||
        hoverBackgroundColor != null ||
        pressedBackgroundColor != null;

    return forui.FButton.icon(
      variant: forui.FButtonVariant.ghost,
      size: forui.FButtonSizeVariant.sm,
      semanticsLabel: tooltipLabel,
      onPress: enabled ? onPressed : null,
      style: customBackground
          ? _iconButtonStyle(
              backgroundColor: effectiveBackground,
              hoverBackgroundColor:
                  hoverBackgroundColor ?? _tintActionColor(effectiveBackground),
              pressedBackgroundColor:
                  pressedBackgroundColor ??
                  _pressActionColor(effectiveBackground),
            )
          : _plainIconButtonStyle,
      child: isSpinner
          ? SpinningIcon(icon: icon, size: 17, color: effectiveForeground)
          : Icon(icon, size: 17, color: effectiveForeground),
    );
  }
}

const _plainIconButtonStyle = forui.FButtonStyleDelta.delta(
  iconContentStyle: forui.FButtonIconContentStyleDelta.delta(
    padding: forui.EdgeInsetsGeometryDelta.value(EdgeInsets.all(7)),
  ),
);

forui.FButtonStyleDelta _iconButtonStyle({
  required Color backgroundColor,
  required Color hoverBackgroundColor,
  required Color pressedBackgroundColor,
}) {
  return forui.FButtonStyleDelta.delta(
    iconContentStyle: const forui.FButtonIconContentStyleDelta.delta(
      padding: forui.EdgeInsetsGeometryDelta.value(EdgeInsets.all(7)),
    ),
    decoration: forui.FVariantsDelta.delta([
      forui.FVariantOperation.base(
        forui.DecorationDelta.value(
          BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      forui.FVariantOperation.exact(
        {forui.FTappableVariantConstraint.hovered},
        forui.DecorationDelta.value(
          BoxDecoration(
            color: hoverBackgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      forui.FVariantOperation.exact(
        {forui.FTappableVariantConstraint.pressed},
        forui.DecorationDelta.value(
          BoxDecoration(
            color: pressedBackgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    ]),
  );
}

class _JobActionColors {
  const _JobActionColors._();

  static const primary = Color(0xFF15803D);
  static const cancel = Color(0xFFB45309);
  static const delete = Color(0xFFEF4444);
}

class _ChildStatusIcon extends StatelessWidget {
  const _ChildStatusIcon({required this.item, required this.color});

  final DownloadItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = _childStatusIcon(item);
    if (item.isSelected && item.status == DownloadStatus.downloading) {
      return SpinningIcon(icon: icon, size: 13, color: color);
    }

    return Icon(icon, size: 13, color: color);
  }
}

Color _tintActionColor(Color color) => Color.lerp(color, Colors.white, 0.08)!;

Color _pressActionColor(Color color) => Color.lerp(color, Colors.black, 0.08)!;

bool _pathExists(String? path) {
  if (path == null || path.trim().isEmpty) return false;
  return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
}

_PrimaryJobAction _primaryActionFor(
  DownloadJob job, {
  required bool canExportManualSegments,
}) {
  if (job.status == DownloadStatus.analyzing) {
    return const _PrimaryJobAction(
      label: 'Wait',
      icon: LucideIcons.loaderCircle,
      isDisabled: true,
      isSpinner: true,
    );
  }
  if (job.status == DownloadStatus.downloading ||
      job.status == DownloadStatus.queued) {
    return const _PrimaryJobAction(
      label: 'Stop',
      icon: LucideIcons.square,
      color: _JobActionColors.cancel,
      isCancel: true,
    );
  }
  if (_hasSelectedManualSegments(job) && canExportManualSegments) {
    return const _PrimaryJobAction(
      label: 'Export',
      icon: LucideIcons.fileOutput,
    );
  }
  if (job.status == DownloadStatus.stopped) {
    return const _PrimaryJobAction(
      label: 'Download',
      icon: LucideIcons.download,
      color: _JobActionColors.cancel,
    );
  }
  if (job.status == DownloadStatus.failed) {
    return const _PrimaryJobAction(label: 'Retry', icon: LucideIcons.rotateCcw);
  }
  return const _PrimaryJobAction(label: 'Download', icon: LucideIcons.download);
}

class _PrimaryJobAction {
  const _PrimaryJobAction({
    required this.label,
    required this.icon,
    this.color = _JobActionColors.primary,
    this.isCancel = false,
    this.isDisabled = false,
    this.isSpinner = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isCancel;
  final bool isDisabled;
  final bool isSpinner;
}

String _jobStatusLine(DownloadJob job) {
  if (job.error != null && job.status == DownloadStatus.failed) {
    return 'Failed: ${job.error}';
  }

  return switch (job.status) {
    DownloadStatus.ready => 'Ready to download',
    DownloadStatus.queued => 'Queued, waiting for an open download slot',
    DownloadStatus.analyzing => 'Reading metadata from ${_sourceLabel(job)}',
    DownloadStatus.stopped =>
      _elapsedLabel(job) == null
          ? 'Stopped by user'
          : 'Stopped by user, ${_elapsedLabel(job)!}',
    DownloadStatus.downloading =>
      _activeChildWorkLabel(job) ??
          (job.startedAt == null
              ? 'Download started'
              : 'Downloading, started ${_formatDateTime(job.startedAt!)}'),
    DownloadStatus.complete =>
      _hasSelectedManualSegments(job)
          ? (_elapsedLabel(job) == null
                ? 'Split export complete'
                : 'Split export complete, ${_elapsedLabel(job)!}')
          : _elapsedLabel(job) == null
          ? 'Download complete'
          : 'Download complete, ${_elapsedLabel(job)!}',
    DownloadStatus.failed =>
      _elapsedLabel(job) == null
          ? 'Download failed'
          : 'Download failed, ${_elapsedLabel(job)!}',
  };
}

String? _activeChildWorkLabel(DownloadJob job) {
  final selectedChildren = job.children.where((child) => child.isSelected);
  if (selectedChildren.isEmpty) return null;
  if (selectedChildren.any(
    (child) => child.kind == DownloadItemKind.manualSegment,
  )) {
    return job.eta.startsWith('Export') ? job.eta : 'Exporting split segments';
  }
  if (selectedChildren.any((child) => child.kind == DownloadItemKind.chapter)) {
    return job.eta.startsWith('Download')
        ? 'Downloading selected chapters • ${job.eta}'
        : job.eta;
  }
  if (selectedChildren.any(
    (child) => child.kind == DownloadItemKind.playlistEntry,
  )) {
    return job.eta.startsWith('Download')
        ? 'Downloading selected playlist entries • ${job.eta}'
        : job.eta;
  }
  return null;
}

Color _statusTextColor(FetchdeckThemeData theme, DownloadStatus status) {
  return switch (status) {
    DownloadStatus.failed => const Color(0xFFB91C1C),
    DownloadStatus.ready || DownloadStatus.complete => const Color(0xFF15803D),
    DownloadStatus.analyzing => const Color(0xFFB45309),
    DownloadStatus.stopped => const Color(0xFFB45309),
    DownloadStatus.downloading => theme.colorScheme.foreground,
    DownloadStatus.queued => theme.colorScheme.mutedForeground,
  };
}

class _AnimatedProgress extends StatelessWidget {
  const _AnimatedProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final clampedValue = value.clamp(0, 1).toDouble();

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: clampedValue),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: theme.colorScheme.muted),
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: animatedValue,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.info});

  final MediaInfo? info;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final thumbnail = info?.thumbnail;

    return SizedBox(
      height: double.infinity,
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            color: theme.colorScheme.muted,
            child: thumbnail == null
                ? Icon(
                    info?.isPlaylist == true
                        ? LucideIcons.listVideo
                        : LucideIcons.video,
                    color: theme.colorScheme.mutedForeground,
                  )
                : Image.network(
                    thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      LucideIcons.video,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

String _sourceLabel(DownloadJob job) {
  final mediaSource = job.mediaInfo?.sourceLabel.trim();
  if (mediaSource != null && mediaSource.isNotEmpty) {
    return _prettySource(mediaSource);
  }

  return _prettySource(job.source);
}

String _prettySource(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Unknown source';

  final parsed = Uri.tryParse(trimmed);
  final host = parsed?.host;
  final source = host == null || host.isEmpty ? trimmed : host;
  final normalized = source.toLowerCase();

  if (normalized.contains('youtube') || normalized == 'youtu.be') {
    return 'YouTube';
  }
  if (normalized.contains('vimeo')) return 'Vimeo';
  if (normalized.contains('soundcloud')) return 'SoundCloud';
  if (normalized.contains('tiktok')) return 'TikTok';
  if (normalized.contains('instagram')) return 'Instagram';
  if (normalized.contains('facebook')) return 'Facebook';
  if (normalized.contains('twitter') || normalized.contains('x.com')) {
    return 'X';
  }

  final withoutWww = source.startsWith('www.') ? source.substring(4) : source;
  if (!withoutWww.contains('.') && withoutWww.length <= 24) return withoutWww;

  return withoutWww
      .split('.')
      .where((part) => part.isNotEmpty)
      .take(2)
      .join('.');
}

String? _childDetailLabel(DownloadItem item) {
  final parts = <String>[
    if ((item.kind == DownloadItemKind.chapter ||
            item.kind == DownloadItemKind.manualSegment) &&
        item.startTime != null &&
        item.endTime != null)
      '${_formatTimestamp(item.startTime!)} - ${_formatTimestamp(item.endTime!)}',
    if (item.kind == DownloadItemKind.playlistEntry && item.source != null)
      item.source!,
    if (item.duration != null) _formatDuration(item.duration!),
  ];

  return parts.isEmpty ? null : parts.join(' • ');
}

bool _hasSelectedManualSegments(DownloadJob job) {
  return job.children.any(
    (child) => child.kind == DownloadItemKind.manualSegment && child.isSelected,
  );
}

String? _childStatusLabel(DownloadItem item) {
  if (!item.isSelected) return 'Skipped';

  return switch ((item.kind, item.status)) {
    (DownloadItemKind.manualSegment, DownloadStatus.ready) => 'Ready',
    (DownloadItemKind.manualSegment, DownloadStatus.queued) => 'Queued',
    (DownloadItemKind.manualSegment, DownloadStatus.downloading) => 'Exporting',
    (DownloadItemKind.manualSegment, DownloadStatus.complete) => 'Exported',
    (
      DownloadItemKind.playlistEntry || DownloadItemKind.chapter,
      DownloadStatus.downloading,
    ) =>
      'Downloading',
    _ => null,
  };
}

bool _locksChildSelection(DownloadStatus status) {
  return status == DownloadStatus.analyzing ||
      status == DownloadStatus.queued ||
      status == DownloadStatus.downloading;
}

Color _childStatusColor(DownloadItem item) {
  if (!item.isSelected) return const Color(0xFF94A3B8);

  return switch (item.status) {
    DownloadStatus.ready => const Color(0xFF38BDF8),
    DownloadStatus.queued => const Color(0xFFF59E0B),
    DownloadStatus.analyzing => const Color(0xFFF97316),
    DownloadStatus.downloading => const Color(0xFF60A5FA),
    DownloadStatus.stopped => const Color(0xFFF97316),
    DownloadStatus.failed => const Color(0xFFEF4444),
    DownloadStatus.complete => const Color(0xFF22C55E),
  };
}

IconData _childStatusIcon(DownloadItem item) {
  if (!item.isSelected) return LucideIcons.circleMinus;

  return switch (item.status) {
    DownloadStatus.ready => LucideIcons.circle,
    DownloadStatus.queued => LucideIcons.clock3,
    DownloadStatus.analyzing => LucideIcons.search,
    DownloadStatus.downloading => LucideIcons.loaderCircle,
    DownloadStatus.stopped => LucideIcons.circlePause,
    DownloadStatus.failed => LucideIcons.circleAlert,
    DownloadStatus.complete => LucideIcons.circleCheck,
  };
}

String _formatTimestamp(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '${value.inMinutes}:$seconds';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final month = _monthLabels[local.month - 1];
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month $day, $hour:$minute';
}

String? _elapsedLabel(DownloadJob job) {
  final startedAt = job.startedAt;
  final completedAt = job.completedAt;
  if (startedAt == null || completedAt == null) return null;

  final elapsed = completedAt.difference(startedAt);
  if (elapsed.isNegative) return null;
  return 'Took ${_formatDuration(elapsed)}';
}

String _formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds}s';

  final minutes = duration.inMinutes;
  final remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return remainingSeconds == 0
        ? '${minutes}m'
        : '${minutes}m ${remainingSeconds}s';
  }

  final hours = duration.inHours;
  final remainingMinutes = minutes % 60;
  return remainingMinutes == 0 ? '${hours}h' : '${hours}h ${remainingMinutes}m';
}

const _monthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

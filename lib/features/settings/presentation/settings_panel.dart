import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as forui;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';

import '../application/download_concurrency_limit.dart';
import '../../../services/tools/tool_discovery.dart';
import '../../../services/tools/yt_dlp_update_service.dart';
import '../../../services/yt_dlp/yt_dlp_authentication.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.toolSet,
    required this.appVersion,
    required this.ytDlpPath,
    required this.ffmpegPath,
    required this.ffprobePath,
    required this.isChecking,
    required this.updateInfo,
    required this.concurrencyLimit,
    required this.authentication,
    required this.isCheckingUpdate,
    required this.isUpdatingYtDlp,
    required this.updateDismissed,
    required this.onPickYtDlp,
    required this.onPickFfmpeg,
    required this.onPickFfprobe,
    required this.onClearYtDlp,
    required this.onClearFfmpeg,
    required this.onClearFfprobe,
    required this.onRecheck,
    required this.onCheckYtDlpUpdate,
    required this.onInstallYtDlpUpdate,
    required this.onSkipYtDlpUpdate,
    required this.onConcurrencyChanged,
    required this.onAuthenticationChanged,
  });

  final ToolSet toolSet;
  final String appVersion;
  final String? ytDlpPath;
  final String? ffmpegPath;
  final String? ffprobePath;
  final bool isChecking;
  final YtDlpUpdateInfo? updateInfo;
  final DownloadConcurrencyLimit concurrencyLimit;
  final YtDlpAuthentication authentication;
  final bool isCheckingUpdate;
  final bool isUpdatingYtDlp;
  final bool updateDismissed;
  final VoidCallback onPickYtDlp;
  final VoidCallback onPickFfmpeg;
  final VoidCallback onPickFfprobe;
  final VoidCallback onClearYtDlp;
  final VoidCallback onClearFfmpeg;
  final VoidCallback onClearFfprobe;
  final VoidCallback onRecheck;
  final VoidCallback onCheckYtDlpUpdate;
  final VoidCallback onInstallYtDlpUpdate;
  final VoidCallback onSkipYtDlpUpdate;
  final ValueChanged<DownloadConcurrencyLimit> onConcurrencyChanged;
  final ValueChanged<YtDlpAuthentication> onAuthenticationChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const _PageHeader(title: 'Settings'),
        const SizedBox(height: 14),
        _SettingsSection(
          title: 'Downloads',
          children: [
            _ConcurrencyRow(
              limit: concurrencyLimit,
              onChanged: onConcurrencyChanged,
            ),
            const SizedBox(height: 10),
            _BrowserCookiesRow(
              authentication: authentication,
              onChanged: onAuthenticationChanged,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: 'Tool Updates',
          children: [
            _YtDlpUpdateRow(
              toolInfo: toolSet.ytDlp,
              updateInfo: updateInfo,
              isChecking: isCheckingUpdate,
              isUpdating: isUpdatingYtDlp,
              updateDismissed: updateDismissed,
              onCheck: onCheckYtDlpUpdate,
              onUpdate: onInstallYtDlpUpdate,
              onSkip: onSkipYtDlpUpdate,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: 'App & Tools',
          children: [
            _TwoColumnInfoGrid(
              children: [
                _SystemInfoChip(
                  icon: LucideIcons.badgeInfo,
                  label: 'Fetchdeck',
                  value: appVersion,
                  healthy: true,
                ),
                const _SystemInfoChip(
                  icon: LucideIcons.circleCheck,
                  label: 'Flutter',
                  value: '3.44.1',
                  healthy: true,
                ),
                _SystemInfoChip(
                  icon: isChecking
                      ? LucideIcons.loaderCircle
                      : toolSet.ytDlp.isAvailable
                      ? LucideIcons.circleCheck
                      : LucideIcons.circleAlert,
                  label: 'yt-dlp',
                  value: isChecking
                      ? 'Checking...'
                      : toolSet.ytDlp.shortLabel('yt-dlp'),
                  healthy: toolSet.ytDlp.isAvailable,
                ),
                _SystemInfoChip(
                  icon: toolSet.ffmpeg.isAvailable
                      ? LucideIcons.circleCheck
                      : LucideIcons.circleAlert,
                  label: 'ffmpeg',
                  value: toolSet.ffmpeg.shortLabel('ffmpeg'),
                  healthy: toolSet.ffmpeg.isAvailable,
                ),
                _SystemInfoChip(
                  icon: toolSet.ffprobe.isAvailable
                      ? LucideIcons.circleCheck
                      : LucideIcons.circleAlert,
                  label: 'ffprobe',
                  value: toolSet.ffprobe.shortLabel('ffprobe'),
                  healthy: toolSet.ffprobe.isAvailable,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _AdvancedSettingsSection(
          toolSet: toolSet,
          ytDlpPath: ytDlpPath,
          ffmpegPath: ffmpegPath,
          ffprobePath: ffprobePath,
          isChecking: isChecking,
          onPickYtDlp: onPickYtDlp,
          onPickFfmpeg: onPickFfmpeg,
          onPickFfprobe: onPickFfprobe,
          onClearYtDlp: onClearYtDlp,
          onClearFfmpeg: onClearFfmpeg,
          onClearFfprobe: onClearFfprobe,
          onRecheck: onRecheck,
        ),
      ],
    );
  }
}

TextStyle _helperTextStyle(FetchdeckThemeData theme) {
  return theme.textTheme.muted.copyWith(
    color: Colors.white.withValues(alpha: 0.68),
  );
}

class _BrowserCookiesRow extends StatefulWidget {
  const _BrowserCookiesRow({
    required this.authentication,
    required this.onChanged,
  });

  final YtDlpAuthentication authentication;
  final ValueChanged<YtDlpAuthentication> onChanged;

  @override
  State<_BrowserCookiesRow> createState() => _BrowserCookiesRowState();
}

class _BrowserCookiesRowState extends State<_BrowserCookiesRow> {
  late final TextEditingController profileController;
  var syncingProfileFromWidget = false;

  @override
  void initState() {
    super.initState();
    profileController = TextEditingController(
      text: widget.authentication.browserProfile ?? '',
    );
    profileController.addListener(_handleProfileChanged);
  }

  @override
  void didUpdateWidget(covariant _BrowserCookiesRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final profile = widget.authentication.browserProfile ?? '';
    if (profile != profileController.text) {
      syncingProfileFromWidget = true;
      profileController.text = profile;
      syncingProfileFromWidget = false;
    }
  }

  @override
  void dispose() {
    profileController.removeListener(_handleProfileChanged);
    profileController.dispose();
    super.dispose();
  }

  void _handleProfileChanged() {
    if (syncingProfileFromWidget) return;
    final profile = profileController.text.trim();
    widget.onChanged(
      widget.authentication.copyWith(
        browserProfile: profile.isEmpty ? null : profile,
        clearBrowserProfile: profile.isEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final showSafariNote =
        widget.authentication.useBrowserCookies &&
        widget.authentication.browser == BrowserCookieSource.safari;
    final showKeychainNote =
        widget.authentication.useBrowserCookies &&
        widget.authentication.browser.mayPromptForKeychain;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.keyRound,
            size: 17,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Browser cookies', style: theme.textTheme.small),
                const SizedBox(height: 5),
                Text(
                  'Use your signed-in browser session for private or account-gated media. Add a profile only if you do not use the default browser profile.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _helperTextStyle(theme),
                ),
                if (showSafariNote) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Safari may require Full Disk Access for Fetchdeck on macOS.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.muted.copyWith(
                      color: const Color(0xFFB45309),
                    ),
                  ),
                ],
                if (showKeychainNote) ...[
                  const SizedBox(height: 5),
                  Text(
                    '${widget.authentication.browser.label} may show a macOS Keychain prompt. Choose Allow or Always Allow, then retry if analysis timed out.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.muted.copyWith(
                      color: const Color(0xFFB45309),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          forui.FSwitch(
            value: widget.authentication.useBrowserCookies,
            onChange: (value) {
              widget.onChanged(
                widget.authentication.copyWith(useBrowserCookies: value),
              );
            },
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: forui.FSelect<BrowserCookieSource>.rich(
              enabled: widget.authentication.useBrowserCookies,
              control: forui.FSelectControl.lifted(
                value: widget.authentication.browser,
                onChange: (value) {
                  if (value != null) {
                    widget.onChanged(
                      widget.authentication.copyWith(browser: value),
                    );
                  }
                },
              ),
              format: (source) => source.label,
              children: [
                for (final source in BrowserCookieSource.values)
                  forui.FSelectItem<BrowserCookieSource>(
                    value: source,
                    title: Text(source.label),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                forui.FTextField(
                  enabled: widget.authentication.useBrowserCookies,
                  control: forui.FTextFieldControl.managed(
                    controller: profileController,
                  ),
                  hint: 'Default, Profile 1',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcurrencyRow extends StatelessWidget {
  const _ConcurrencyRow({required this.limit, required this.onChanged});

  final DownloadConcurrencyLimit limit;
  final ValueChanged<DownloadConcurrencyLimit> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.listStart,
            size: 17,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Concurrent downloads', style: theme.textTheme.small),
                const SizedBox(height: 5),
                Text(
                  'Controls how many queued jobs Start All may run at once.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _helperTextStyle(theme),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: forui.FSelect<DownloadConcurrencyLimit>.rich(
              control: forui.FSelectControl.lifted(
                value: limit,
                onChange: (value) {
                  if (value != null) onChanged(value);
                },
              ),
              format: (option) => option.label,
              children: [
                for (final option in DownloadConcurrencyLimit.values)
                  forui.FSelectItem<DownloadConcurrencyLimit>(
                    value: option,
                    title: Text(option.label),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedSettingsSection extends StatelessWidget {
  const _AdvancedSettingsSection({
    required this.toolSet,
    required this.ytDlpPath,
    required this.ffmpegPath,
    required this.ffprobePath,
    required this.isChecking,
    required this.onPickYtDlp,
    required this.onPickFfmpeg,
    required this.onPickFfprobe,
    required this.onClearYtDlp,
    required this.onClearFfmpeg,
    required this.onClearFfprobe,
    required this.onRecheck,
  });

  final ToolSet toolSet;
  final String? ytDlpPath;
  final String? ffmpegPath;
  final String? ffprobePath;
  final bool isChecking;
  final VoidCallback onPickYtDlp;
  final VoidCallback onPickFfmpeg;
  final VoidCallback onPickFfprobe;
  final VoidCallback onClearYtDlp;
  final VoidCallback onClearFfmpeg;
  final VoidCallback onClearFfprobe;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: forui.FAccordion(
        children: [
          forui.FAccordionItem(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Advanced', style: theme.textTheme.large),
                const SizedBox(height: 2),
                Text(
                  'Manual tool paths and technical diagnostics.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _helperTextStyle(theme),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text('Tool Paths', style: theme.textTheme.small),
                    ),
                    forui.FButton(
                      variant: forui.FButtonVariant.outline,
                      size: forui.FButtonSizeVariant.sm,
                      onPress: isChecking ? null : onRecheck,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isChecking
                                ? LucideIcons.loaderCircle
                                : LucideIcons.refreshCw,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(isChecking ? 'Checking' : 'Re-check'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ToolPathRow(
                  label: 'yt-dlp',
                  path: ytDlpPath,
                  info: toolSet.ytDlp,
                  onChoose: onPickYtDlp,
                  onClear: onClearYtDlp,
                ),
                const SizedBox(height: 10),
                _ToolPathRow(
                  label: 'ffmpeg',
                  path: ffmpegPath,
                  info: toolSet.ffmpeg,
                  onChoose: onPickFfmpeg,
                  onClear: onClearFfmpeg,
                ),
                const SizedBox(height: 10),
                _ToolPathRow(
                  label: 'ffprobe',
                  path: ffprobePath,
                  info: toolSet.ffprobe,
                  onChoose: onPickFfprobe,
                  onClear: onClearFfprobe,
                ),
                const SizedBox(height: 16),
                Text('Engine Details', style: theme.textTheme.small),
                const SizedBox(height: 10),
                const _InlineFact(
                  icon: LucideIcons.terminal,
                  text:
                      'Fetchdeck calls yt-dlp through Process.start with structured arguments and progress templates.',
                ),
                const SizedBox(height: 10),
                const _InlineFact(
                  icon: LucideIcons.folderOpen,
                  text:
                      'Downloads use the selected output folder and user-selected file access.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return SizedBox(
      height: 38,
      child: Row(
        children: [Expanded(child: Text(title, style: theme.textTheme.h4))],
      ),
    );
  }
}

class _InlineFact extends StatelessWidget {
  const _InlineFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.mutedForeground),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.muted)),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.large),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _TwoColumnInfoGrid extends StatelessWidget {
  const _TwoColumnInfoGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index += 2) {
      rows.add(
        Row(
          children: [
            Expanded(child: children[index]),
            const SizedBox(width: 8),
            Expanded(
              child: index + 1 < children.length
                  ? children[index + 1]
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      if (index + 2 < children.length) {
        rows.add(const SizedBox(height: 8));
      }
    }

    return Column(children: rows);
  }
}

class _SystemInfoChip extends StatelessWidget {
  const _SystemInfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.healthy,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: healthy
                ? const Color(0xFF15803D)
                : theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.small.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _helperTextStyle(theme),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolPathRow extends StatelessWidget {
  const _ToolPathRow({
    required this.label,
    required this.path,
    required this.info,
    required this.onChoose,
    required this.onClear,
  });

  final String label;
  final String? path;
  final ToolInfo info;
  final VoidCallback onChoose;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final healthy = info.isAvailable;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            healthy ? LucideIcons.circleCheck : LucideIcons.circleAlert,
            size: 17,
            color: healthy
                ? const Color(0xFF15803D)
                : theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: theme.textTheme.small),
                    const SizedBox(width: 8),
                    Text(
                      healthy
                          ? 'Available • ${info.source?.label ?? 'System'}'
                          : info.path == null
                          ? 'Missing'
                          : 'Blocked • ${info.source?.label ?? 'Unknown'}',
                      style: theme.textTheme.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  info.path ??
                      path ??
                      'Auto-detect bundled tools, PATH, and common install folders',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _helperTextStyle(theme),
                ),
                if (info.version != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    info.version!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.small,
                  ),
                ],
                if (!info.isAvailable && info.error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    info.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.small,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          forui.FButton(
            variant: forui.FButtonVariant.outline,
            size: forui.FButtonSizeVariant.sm,
            onPress: onChoose,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.folderOpen, size: 15),
                SizedBox(width: 6),
                Text('Choose'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          forui.FButton.icon(
            variant: forui.FButtonVariant.ghost,
            size: forui.FButtonSizeVariant.sm,
            onPress: path == null ? null : onClear,
            child: const Icon(LucideIcons.x, size: 16),
          ),
        ],
      ),
    );
  }
}

class _YtDlpUpdateRow extends StatelessWidget {
  const _YtDlpUpdateRow({
    required this.toolInfo,
    required this.updateInfo,
    required this.isChecking,
    required this.isUpdating,
    required this.updateDismissed,
    required this.onCheck,
    required this.onUpdate,
    required this.onSkip,
  });

  final ToolInfo toolInfo;
  final YtDlpUpdateInfo? updateInfo;
  final bool isChecking;
  final bool isUpdating;
  final bool updateDismissed;
  final VoidCallback onCheck;
  final VoidCallback onUpdate;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final updateAvailable =
        updateInfo?.updateAvailable == true && !updateDismissed;
    final currentVersion = updateInfo?.currentVersion ?? toolInfo.version;
    final latestVersion = updateInfo?.latestVersion;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            updateAvailable
                ? LucideIcons.circleArrowUp
                : LucideIcons.circleCheck,
            size: 17,
            color: updateAvailable
                ? const Color(0xFFB45309)
                : const Color(0xFF15803D),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('yt-dlp', style: theme.textTheme.small),
                    const SizedBox(width: 8),
                    Text(
                      updateAvailable ? 'Update available' : 'Updates',
                      style: theme.textTheme.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _versionText(currentVersion, latestVersion, updateDismissed),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _helperTextStyle(theme),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (updateAvailable) ...[
            forui.FButton(
              size: forui.FButtonSizeVariant.sm,
              onPress: isUpdating ? null : onUpdate,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUpdating
                        ? LucideIcons.loaderCircle
                        : LucideIcons.download,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Text(isUpdating ? 'Updating' : 'Update'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            forui.FButton(
              variant: forui.FButtonVariant.outline,
              size: forui.FButtonSizeVariant.sm,
              onPress: isUpdating ? null : onSkip,
              child: const Text('Skip'),
            ),
          ] else
            forui.FButton(
              variant: forui.FButtonVariant.outline,
              size: forui.FButtonSizeVariant.sm,
              onPress: isChecking || isUpdating ? null : onCheck,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isChecking
                        ? LucideIcons.loaderCircle
                        : LucideIcons.refreshCw,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Text(isChecking ? 'Checking' : 'Check'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _versionText(
    String? currentVersion,
    String? latestVersion,
    bool dismissed,
  ) {
    final current = currentVersion ?? 'unknown';
    if (latestVersion == null) return 'Current version: $current';
    if (dismissed) {
      return 'Current version: $current. Latest $latestVersion skipped for now.';
    }
    return 'Current version: $current. Latest version: $latestVersion.';
  }
}

import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as forui;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final items = <({IconData icon, String label})>[
      (icon: LucideIcons.download, label: 'Downloads'),
      (icon: LucideIcons.slidersHorizontal, label: 'Presets'),
      (icon: LucideIcons.settings, label: 'Settings'),
    ];

    return Container(
      width: 220,
      color: theme.colorScheme.muted.withValues(alpha: 0.38),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Fetchdeck',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.large,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _NavButton(
                      icon: item.icon,
                      label: item.label,
                      selected: selected == item.label,
                      onPressed: () => onSelected(item.label),
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const selectedForeground = Colors.black;
    final theme = FetchdeckTheme.of(context);
    final foreground = selected
        ? selectedForeground
        : theme.colorScheme.foreground.withValues(alpha: 0.84);

    return forui.FButton.raw(
      variant: forui.FButtonVariant.ghost,
      onPress: onPressed,
      style: _navButtonStyle(selected: selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: SizedBox(
          width: double.infinity,
          child: IconTheme(
            data: IconThemeData(color: foreground, size: 17),
            child: DefaultTextStyle.merge(
              style: theme.textTheme.p.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(icon, size: 17),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

forui.FButtonStyleDelta _navButtonStyle({required bool selected}) {
  const selectedBackground = Colors.white;
  final idleBackground = selected ? selectedBackground : Colors.transparent;
  final hoverBackground = selected
      ? selectedBackground
      : Colors.white.withValues(alpha: 0.08);
  final pressedBackground = selected
      ? selectedBackground
      : Colors.white.withValues(alpha: 0.12);

  return forui.FButtonStyleDelta.delta(
    contentStyle: const forui.FButtonContentStyleDelta.delta(
      padding: forui.EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
    ),
    decoration: forui.FVariantsDelta.delta([
      forui.FVariantOperation.base(
        forui.DecorationDelta.value(
          BoxDecoration(
            color: idleBackground,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      forui.FVariantOperation.exact(
        {forui.FTappableVariantConstraint.hovered},
        forui.DecorationDelta.value(
          BoxDecoration(
            color: hoverBackground,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      forui.FVariantOperation.exact(
        {forui.FTappableVariantConstraint.pressed},
        forui.DecorationDelta.value(
          BoxDecoration(
            color: pressedBackground,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    ]),
  );
}

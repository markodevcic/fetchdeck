import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as forui;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';

import '../../../models/download_models.dart';
import '../../../shared/presentation/spinning_icon.dart';

class DownloadToolbar extends StatelessWidget {
  const DownloadToolbar({
    super.key,
    required this.controller,
    required this.presets,
    required this.selectedPreset,
    required this.isAnalyzing,
    required this.outputDirectory,
    required this.onPresetChanged,
    required this.onAdd,
    required this.onPaste,
    required this.onPickOutput,
  });

  final TextEditingController controller;
  final List<PresetDefinition> presets;
  final PresetDefinition selectedPreset;
  final bool isAnalyzing;
  final String? outputDirectory;
  final ValueChanged<PresetDefinition> onPresetChanged;
  final VoidCallback onAdd;
  final VoidCallback onPaste;
  final VoidCallback onPickOutput;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final inputRow = Row(
            children: [
              Expanded(
                child: _UrlInput(controller: controller, onAdd: onAdd),
              ),
              const SizedBox(width: 8),
              _IconTooltip(
                message: 'Paste from clipboard',
                child: forui.FButton.icon(
                  variant: forui.FButtonVariant.outline,
                  size: forui.FButtonSizeVariant.md,
                  semanticsLabel: 'Paste from clipboard',
                  onPress: onPaste,
                  child: const Icon(LucideIcons.clipboard, size: 16),
                ),
              ),
            ],
          );
          final controlsRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                child: forui.FSelect<PresetDefinition>.rich(
                  hint: 'Preset',
                  format: (preset) => preset.label,
                  control: forui.FSelectControl.lifted(
                    value: selectedPreset,
                    onChange: (value) {
                      if (value != null) onPresetChanged(value);
                    },
                  ),
                  children: [
                    for (final preset in presets)
                      forui.FSelectItem<PresetDefinition>(
                        title: Text(preset.label),
                        value: preset,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              forui.FButton(
                mainAxisSize: MainAxisSize.min,
                onPress: onAdd,
                prefix: isAnalyzing
                    ? const SpinningIcon(
                        icon: LucideIcons.loaderCircle,
                        size: 16,
                      )
                    : const Icon(LucideIcons.plus, size: 16),
                child: Text(isAnalyzing ? 'Analyzing' : 'Add'),
              ),
              const SizedBox(width: 8),
              forui.FButton(
                variant: forui.FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: onPickOutput,
                prefix: Icon(
                  LucideIcons.folderOpen,
                  size: 16,
                  color: theme.colorScheme.foreground,
                ),
                child: const Text('Output'),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                inputRow,
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: controlsRow,
                ),
              ] else
                Row(
                  children: [
                    Expanded(child: inputRow),
                    const SizedBox(width: 12),
                    controlsRow,
                  ],
                ),
            ],
          );
        },
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

class _UrlInput extends StatelessWidget {
  const _UrlInput({required this.controller, required this.onAdd});

  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return forui.FTextField(
      control: forui.FTextFieldControl.managed(controller: controller),
      hint: 'Paste a video, playlist, channel, or batch URL',
      prefixBuilder: (_, _, _) => const Padding(
        padding: EdgeInsetsDirectional.only(start: 12, end: 4),
        child: Icon(LucideIcons.link, size: 16),
      ),
      onSubmit: (_) => onAdd(),
    );
  }
}

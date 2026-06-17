// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as forui;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';

import '../../../models/download_models.dart';

TextStyle _presetHelperTextStyle(FetchdeckThemeData theme) {
  return theme.textTheme.muted.copyWith(
    color: Colors.white.withValues(alpha: 0.68),
  );
}

class PresetsPanel extends StatelessWidget {
  const PresetsPanel({
    super.key,
    required this.presets,
    required this.selectedPreset,
    required this.onSelected,
    required this.onCreate,
    required this.onDelete,
  });

  final List<PresetDefinition> presets;
  final PresetDefinition selectedPreset;
  final ValueChanged<PresetDefinition> onSelected;
  final VoidCallback onCreate;
  final ValueChanged<PresetDefinition> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 38,
          child: Row(
            children: [
              Expanded(child: Text('Presets', style: theme.textTheme.h4)),
              SizedBox(
                width: 196,
                child: forui.FButton(
                  variant: forui.FButtonVariant.outline,
                  size: forui.FButtonSizeVariant.sm,
                  onPress: onCreate,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.plus, size: 15),
                      SizedBox(width: 6),
                      Text('New Preset'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: ListView.separated(
                  itemCount: presets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final preset = presets[index];
                    return _PresetRow(
                      preset: preset,
                      selected: preset == selectedPreset,
                      onPressed: () => onSelected(preset),
                    );
                  },
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: _PresetDetails(
                  preset: selectedPreset,
                  onDelete: selectedPreset.isBuiltIn
                      ? null
                      : () => onDelete(selectedPreset),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.preset,
    required this.selected,
    required this.onPressed,
  });

  final PresetDefinition preset;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return InkWell(
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : null,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.muted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                preset.looksAudio ? LucideIcons.audioLines : LucideIcons.video,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preset.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _presetHelperTextStyle(theme),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetDetails extends StatelessWidget {
  const _PresetDetails({required this.preset, required this.onDelete});

  final PresetDefinition preset;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final summary = _PresetSummary.fromPreset(preset);

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
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Selected Preset', style: theme.textTheme.large),
                  const SizedBox(height: 6),
                  Text(preset.label, style: _presetHelperTextStyle(theme)),
                  if (!preset.isBuiltIn) ...[
                    const SizedBox(height: 10),
                    const _PresetTypeBadge(),
                  ],
                  const SizedBox(height: 16),
                  Text('What It Does', style: theme.textTheme.small),
                  const SizedBox(height: 8),
                  Text(
                    preset.description,
                    style: _presetHelperTextStyle(theme),
                  ),
                  const SizedBox(height: 16),
                  _PresetFacts(summary: summary),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in summary.tags) _PresetTag(label: tag),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(height: 16),
            forui.FButton(
              variant: forui.FButtonVariant.destructive,
              onPress: onDelete,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.trash2, size: 15),
                  SizedBox(width: 6),
                  Text('Delete Preset'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetFacts extends StatelessWidget {
  const _PresetFacts({required this.summary});

  final _PresetSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PresetFact(label: 'Type', value: summary.type),
        _PresetFact(label: 'Format', value: summary.format),
        _PresetFact(label: 'Quality', value: summary.quality),
        _PresetFact(label: 'Includes', value: summary.includes),
      ],
    );
  }
}

class _PresetFact extends StatelessWidget {
  const _PresetFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _presetHelperTextStyle(theme),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetTag extends StatelessWidget {
  const _PresetTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.small),
    );
  }
}

class _PresetSummary {
  const _PresetSummary({
    required this.type,
    required this.format,
    required this.quality,
    required this.includes,
    required this.tags,
  });

  final String type;
  final String format;
  final String quality;
  final String includes;
  final List<String> tags;

  factory _PresetSummary.fromPreset(PresetDefinition preset) {
    final arguments = preset.arguments;
    final text = arguments.join(' ').toLowerCase();
    final isAudio = preset.looksAudio;
    final format = _format(arguments, text, isAudio);
    final quality = _quality(arguments, text);
    final includes = _includes(text, isAudio);
    final tags = <String>[
      isAudio ? 'Audio' : 'Video',
      format,
      if (quality != 'Best available') quality,
      if (text.contains('--embed-metadata')) 'Metadata',
      if (text.contains('--embed-thumbnail')) 'Thumbnail',
    ];

    return _PresetSummary(
      type: isAudio ? 'Audio download' : 'Video download',
      format: format,
      quality: quality,
      includes: includes,
      tags: tags,
    );
  }

  static String _format(List<String> arguments, String text, bool isAudio) {
    final audioFormatIndex = arguments.indexOf('--audio-format');
    if (audioFormatIndex >= 0 && audioFormatIndex + 1 < arguments.length) {
      return arguments[audioFormatIndex + 1].toUpperCase();
    }
    final mergeFormatIndex = arguments.indexOf('--merge-output-format');
    if (mergeFormatIndex >= 0 && mergeFormatIndex + 1 < arguments.length) {
      return arguments[mergeFormatIndex + 1].toUpperCase();
    }
    if (text.contains('mp4')) return 'MP4';
    return isAudio ? 'Original audio' : 'Best available';
  }

  static String _quality(List<String> arguments, String text) {
    final audioQualityIndex = arguments.indexOf('--audio-quality');
    if (audioQualityIndex >= 0 && audioQualityIndex + 1 < arguments.length) {
      final rawQuality = arguments[audioQualityIndex + 1].trim();
      if (rawQuality.toLowerCase().endsWith('k')) {
        return '${rawQuality.substring(0, rawQuality.length - 1)} kbps';
      }
      return rawQuality;
    }
    if (text.contains('height<=1080')) return 'Up to 1080p';
    return 'Best available';
  }

  static String _includes(String text, bool isAudio) {
    final parts = <String>[
      if (isAudio) 'Audio extraction',
      if (text.contains('--embed-metadata')) 'metadata',
      if (text.contains('--embed-thumbnail')) 'thumbnail',
      if (text.contains('--merge-output-format')) 'merge when needed',
    ];
    return parts.isEmpty ? 'Best matching source media' : parts.join(', ');
  }
}

class _PresetTypeBadge extends StatelessWidget {
  const _PresetTypeBadge();

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('Custom', style: theme.textTheme.small),
    );
  }
}

class PresetEditorDialog extends StatefulWidget {
  const PresetEditorDialog({super.key});

  @override
  State<PresetEditorDialog> createState() => _PresetEditorDialogState();
}

class _PresetEditorDialogState extends State<PresetEditorDialog> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final argumentsController = TextEditingController();
  var recipeType = _PresetRecipeType.audio;
  var audioFormat = _AudioPresetFormat.mp3;
  var audioQuality = _AudioPresetQuality.k320;
  var videoFormat = _VideoPresetFormat.mp4;
  var videoQuality = _VideoPresetQuality.p1080;
  var includeMetadata = true;
  var includeThumbnail = true;
  String? error;

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    argumentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);
    final isAudio = recipeType == _PresetRecipeType.audio;

    return forui.FDialog.adaptive(
      constraints: const BoxConstraints(maxWidth: 560),
      title: const Text('New Preset'),
      body: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  forui.FTextFormField(
                    control: forui.FTextFieldControl.managed(
                      controller: nameController,
                    ),
                    label: const Text('Name'),
                    hint: 'Roadtrip MP3',
                    description: const Text('Shown in the preset list.'),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Name is required.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  forui.FTextFormField(
                    control: forui.FTextFieldControl.managed(
                      controller: descriptionController,
                    ),
                    label: const Text('Description'),
                    hint: 'Offline audio for the car',
                    description: const Text(
                      'Optional. Fetchdeck can generate one from your choices.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: forui.FSelect<_PresetRecipeType>.rich(
                          control: forui.FSelectControl.lifted(
                            value: recipeType,
                            onChange: (value) {
                              if (value != null) {
                                setState(() => recipeType = value);
                              }
                            },
                          ),
                          format: (value) => value.label,
                          children: [
                            for (final option in _PresetRecipeType.values)
                              forui.FSelectItem<_PresetRecipeType>(
                                value: option,
                                title: Text(option.label),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: isAudio
                            ? forui.FSelect<_AudioPresetFormat>.rich(
                                control: forui.FSelectControl.lifted(
                                  value: audioFormat,
                                  onChange: (value) {
                                    if (value != null) {
                                      setState(() => audioFormat = value);
                                    }
                                  },
                                ),
                                format: (value) => value.label,
                                children: [
                                  for (final option
                                      in _AudioPresetFormat.values)
                                    forui.FSelectItem<_AudioPresetFormat>(
                                      value: option,
                                      title: Text(option.label),
                                    ),
                                ],
                              )
                            : forui.FSelect<_VideoPresetFormat>.rich(
                                control: forui.FSelectControl.lifted(
                                  value: videoFormat,
                                  onChange: (value) {
                                    if (value != null) {
                                      setState(() => videoFormat = value);
                                    }
                                  },
                                ),
                                format: (value) => value.label,
                                children: [
                                  for (final option
                                      in _VideoPresetFormat.values)
                                    forui.FSelectItem<_VideoPresetFormat>(
                                      value: option,
                                      title: Text(option.label),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: isAudio
                            ? forui.FSelect<_AudioPresetQuality>.rich(
                                control: forui.FSelectControl.lifted(
                                  value: audioQuality,
                                  onChange: (value) {
                                    if (value != null) {
                                      setState(() => audioQuality = value);
                                    }
                                  },
                                ),
                                format: (value) => value.label,
                                children: [
                                  for (final option
                                      in _AudioPresetQuality.values)
                                    forui.FSelectItem<_AudioPresetQuality>(
                                      value: option,
                                      title: Text(option.label),
                                    ),
                                ],
                              )
                            : forui.FSelect<_VideoPresetQuality>.rich(
                                control: forui.FSelectControl.lifted(
                                  value: videoQuality,
                                  onChange: (value) {
                                    if (value != null) {
                                      setState(() => videoQuality = value);
                                    }
                                  },
                                ),
                                format: (value) => value.label,
                                children: [
                                  for (final option
                                      in _VideoPresetQuality.values)
                                    forui.FSelectItem<_VideoPresetQuality>(
                                      value: option,
                                      title: Text(option.label),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PresetToggleRow(
                    icon: LucideIcons.fileAudio,
                    title: 'Embed metadata',
                    description:
                        'Save title, artist, album, and similar tags when available.',
                    value: includeMetadata,
                    onChanged: (value) =>
                        setState(() => includeMetadata = value),
                  ),
                  const SizedBox(height: 8),
                  _PresetToggleRow(
                    icon: LucideIcons.image,
                    title: 'Embed thumbnail',
                    description:
                        'Use the source artwork as the file cover when possible.',
                    value: includeThumbnail,
                    onChanged: (value) =>
                        setState(() => includeThumbnail = value),
                  ),
                  const SizedBox(height: 14),
                  forui.FAccordion(
                    children: [
                      forui.FAccordionItem(
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Advanced', style: theme.textTheme.small),
                            const SizedBox(height: 2),
                            Text(
                              'Optional raw yt-dlp arguments for power users.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _presetHelperTextStyle(theme),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Raw arguments override the friendly options above.',
                                style: _presetHelperTextStyle(theme),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: argumentsController,
                                minLines: 5,
                                maxLines: 7,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: '-f\nba\n-x\n--audio-format\nmp3',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: theme.textTheme.small.copyWith(
                        color: const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        forui.FButton(onPress: _submit, child: const Text('Create')),
        forui.FButton(
          variant: forui.FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  void _submit() {
    setState(() => error = null);
    final isValid = formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    final advancedArguments = _parseAdvancedArguments();
    final arguments = advancedArguments.isEmpty
        ? _buildFriendlyArguments()
        : advancedArguments;

    if (arguments.isEmpty) {
      setState(() => error = 'At least one yt-dlp argument is required.');
      return;
    }

    Navigator.of(context).pop(
      PresetDefinition(
        id: 'custom:${DateTime.now().microsecondsSinceEpoch}',
        label: nameController.text.trim(),
        description: descriptionController.text.trim().isEmpty
            ? _defaultDescription()
            : descriptionController.text.trim(),
        commandSummary: arguments.join(' '),
        arguments: arguments,
        isBuiltIn: false,
      ),
    );
  }

  List<String> _parseAdvancedArguments() {
    return argumentsController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _buildFriendlyArguments() {
    if (recipeType == _PresetRecipeType.audio) {
      final arguments = <String>['-f', 'ba', '-x'];
      if (audioFormat != _AudioPresetFormat.original) {
        arguments.addAll(['--audio-format', audioFormat.argumentValue]);
      }
      if (audioQuality != _AudioPresetQuality.best &&
          audioFormat != _AudioPresetFormat.original) {
        arguments.addAll(['--audio-quality', audioQuality.argumentValue]);
      }
      if (includeMetadata) arguments.add('--embed-metadata');
      if (includeThumbnail) arguments.add('--embed-thumbnail');
      return arguments;
    }

    final selector = videoQuality.selector;
    final arguments = <String>['-f', selector];
    if (videoFormat != _VideoPresetFormat.original) {
      arguments.addAll(['--merge-output-format', videoFormat.argumentValue]);
    }
    if (includeMetadata) arguments.add('--embed-metadata');
    if (includeThumbnail) arguments.add('--embed-thumbnail');
    return arguments;
  }

  String _defaultDescription() {
    if (recipeType == _PresetRecipeType.audio) {
      final format = audioFormat.label.toLowerCase();
      final quality = audioQuality == _AudioPresetQuality.best
          ? 'best available quality'
          : audioQuality.label.toLowerCase();
      return 'Download audio as $format at $quality.';
    }
    final format = videoFormat.label.toLowerCase();
    return 'Download video as $format at ${videoQuality.label.toLowerCase()}.';
  }
}

class _PresetToggleRow extends StatelessWidget {
  const _PresetToggleRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FetchdeckTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.mutedForeground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.small),
                const SizedBox(height: 3),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _presetHelperTextStyle(theme),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          forui.FSwitch(value: value, onChange: onChanged),
        ],
      ),
    );
  }
}

enum _PresetRecipeType {
  audio('Audio'),
  video('Video');

  const _PresetRecipeType(this.label);

  final String label;
}

enum _AudioPresetFormat {
  mp3('MP3', 'mp3'),
  m4a('M4A', 'm4a'),
  opus('Opus', 'opus'),
  original('Original', '');

  const _AudioPresetFormat(this.label, this.argumentValue);

  final String label;
  final String argumentValue;
}

enum _AudioPresetQuality {
  best('Best', ''),
  k320('320 kbps', '320K'),
  k256('256 kbps', '256K'),
  k192('192 kbps', '192K');

  const _AudioPresetQuality(this.label, this.argumentValue);

  final String label;
  final String argumentValue;
}

enum _VideoPresetFormat {
  mp4('MP4', 'mp4'),
  mkv('MKV', 'mkv'),
  original('Original', '');

  const _VideoPresetFormat(this.label, this.argumentValue);

  final String label;
  final String argumentValue;
}

enum _VideoPresetQuality {
  best('Best available', 'bv*+ba/b'),
  p1080('Up to 1080p', 'bv*[height<=1080]+ba/b[height<=1080]'),
  p720('Up to 720p', 'bv*[height<=720]+ba/b[height<=720]');

  const _VideoPresetQuality(this.label, this.selector);

  final String label;
  final String selector;
}

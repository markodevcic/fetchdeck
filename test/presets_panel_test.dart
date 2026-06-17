import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as forui;
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';
import 'package:yt_dlp_desktop/features/presets/presentation/presets_panel.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';

void main() {
  testWidgets('selected preset details hide raw arguments', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: forui.FTheme(
          data: forui.FThemes.zinc.dark.desktop,
          child: Scaffold(
            body: SizedBox(
              width: 900,
              height: 600,
              child: PresetsPanel(
                presets: PresetDefinition.builtIns,
                selectedPreset: PresetDefinition.defaultPreset,
                onSelected: (_) {},
                onCreate: () {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Selected Preset'), findsOneWidget);
    expect(find.text('What It Does'), findsOneWidget);
    expect(find.text('Arguments'), findsNothing);
    expect(find.text('Command Summary'), findsNothing);
    expect(find.textContaining('--audio-format'), findsNothing);
    expect(find.text('320 kbps'), findsWidgets);
  });

  testWidgets('new preset creates friendly mp3 recipe by default', (
    tester,
  ) async {
    PresetDefinition? created;
    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: forui.FTheme(
          data: forui.FThemes.zinc.dark.desktop,
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: forui.FButton(
                    onPress: () async {
                      created = await forui.showFDialog<PresetDefinition>(
                        context: context,
                        builder: (_, _, _) => const PresetEditorDialog(),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'Roadtrip MP3');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.label, 'Roadtrip MP3');
    expect(created!.arguments, containsAll(['-x', '--audio-format', 'mp3']));
    expect(created!.arguments, containsAll(['--audio-quality', '320K']));
    expect(created!.arguments, contains('--embed-metadata'));
    expect(created!.arguments, contains('--embed-thumbnail'));
  });

  testWidgets('advanced arguments override friendly preset choices', (
    tester,
  ) async {
    PresetDefinition? created;
    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: forui.FTheme(
          data: forui.FThemes.zinc.dark.desktop,
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: forui.FButton(
                    onPress: () async {
                      created = await forui.showFDialog<PresetDefinition>(
                        context: context,
                        builder: (_, _, _) => const PresetEditorDialog(),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'Raw Opus');
    await tester.ensureVisible(find.text('Advanced'));
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '-f\nba\n-x\n--audio-format\nopus',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.arguments, ['-f', 'ba', '-x', '--audio-format', 'opus']);
  });
}

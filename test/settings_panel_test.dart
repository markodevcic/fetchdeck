import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/shared/presentation/fetchdeck_theme.dart';
import 'package:yt_dlp_desktop/features/settings/application/download_concurrency_limit.dart';
import 'package:yt_dlp_desktop/features/settings/presentation/settings_panel.dart';
import 'package:yt_dlp_desktop/services/tools/tool_discovery.dart';
import 'package:yt_dlp_desktop/services/yt_dlp/yt_dlp_authentication.dart';

void main() {
  testWidgets('keeps manual tool controls inside Advanced', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fetchdeckMaterialTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 900,
            child: SettingsPanel(
              toolSet: _toolSet(),
              appVersion: '1.0.0 (1)',
              ytDlpPath: '/tools/yt-dlp',
              ffmpegPath: '/tools/ffmpeg',
              ffprobePath: '/tools/ffprobe',
              isChecking: false,
              updateInfo: null,
              concurrencyLimit: DownloadConcurrencyLimit.one,
              authentication: const YtDlpAuthentication(),
              isCheckingUpdate: false,
              isUpdatingYtDlp: false,
              updateDismissed: false,
              onPickYtDlp: () {},
              onPickFfmpeg: () {},
              onPickFfprobe: () {},
              onClearYtDlp: () {},
              onClearFfmpeg: () {},
              onClearFfprobe: () {},
              onRecheck: () {},
              onCheckYtDlpUpdate: () {},
              onInstallYtDlpUpdate: () {},
              onSkipYtDlpUpdate: () {},
              onConcurrencyChanged: (_) {},
              onAuthenticationChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Tool Updates'), findsOneWidget);
    expect(find.text('App & Tools'), findsOneWidget);
    expect(find.text('Tool Paths'), findsNothing);
    expect(find.text('Engine Details'), findsNothing);
    expect(find.text('Choose'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Advanced'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Advanced'), findsOneWidget);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    expect(find.text('Tool Paths'), findsOneWidget);
    expect(find.text('Engine Details'), findsOneWidget);
    expect(find.text('Choose'), findsNWidgets(3));
  });
}

ToolSet _toolSet() {
  return const ToolSet(
    ytDlp: ToolInfo.available(
      path: '/tools/yt-dlp',
      version: '2026.03.17',
      source: ToolSource.bundled,
    ),
    ffmpeg: ToolInfo.available(
      path: '/tools/ffmpeg',
      version: '8.1',
      source: ToolSource.bundled,
    ),
    ffprobe: ToolInfo.available(
      path: '/tools/ffprobe',
      version: '8.1',
      source: ToolSource.bundled,
    ),
  );
}

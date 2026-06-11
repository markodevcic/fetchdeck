import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/main.dart';

void main() {
  testWidgets('renders the download workbench', (tester) async {
    await tester.pumpWidget(const FetchdeckApp(enableToolInspection: false));

    expect(find.text('Fetchdeck'), findsOneWidget);
    expect(find.text('Download Queue'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('No analyzed URLs yet'), findsOneWidget);
    expect(find.text('MP3 320'), findsWidgets);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

final appInfoProvider = FutureProvider<AppInfo>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppInfo(
    name: info.appName.isEmpty ? 'Fetchdeck' : info.appName,
    version: info.version,
    buildNumber: info.buildNumber,
  );
});

class AppInfo {
  const AppInfo({
    required this.name,
    required this.version,
    required this.buildNumber,
  });

  final String name;
  final String version;
  final String buildNumber;

  String get displayVersion {
    if (buildNumber.isEmpty) return version;
    return '$version ($buildNumber)';
  }
}

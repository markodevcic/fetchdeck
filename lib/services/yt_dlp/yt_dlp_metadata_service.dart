import '../../models/download_models.dart';
import 'yt_dlp_authentication.dart';

abstract interface class YtDlpMetadataService {
  Future<MediaInfo> getMetadata(
    String url, {
    YtDlpAuthentication authentication = YtDlpAuthentication.none,
  });
}

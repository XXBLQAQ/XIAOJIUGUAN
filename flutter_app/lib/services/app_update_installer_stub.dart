import 'app_update_installer.dart';

Future<void> downloadAndInstallUpdatePlatform({
  required String downloadUrl,
  required String? expectedSha256,
  required UpdateCancellationToken cancellationToken,
  void Function(double progress)? onProgress,
}) async {
  throw UnsupportedError('当前平台不支持 Android APK 自动安装');
}

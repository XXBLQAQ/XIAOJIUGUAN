import 'app_update_installer_stub.dart'
    if (dart.library.io) 'app_update_installer_io.dart';

class UpdateDownloadCancelled implements Exception {
  const UpdateDownloadCancelled();

  @override
  String toString() => '更新下载已取消';
}

class UpdateCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

Future<void> downloadAndInstallUpdate({
  required String downloadUrl,
  required String? expectedSha256,
  required UpdateCancellationToken cancellationToken,
  void Function(double progress)? onProgress,
}) =>
    downloadAndInstallUpdatePlatform(
      downloadUrl: downloadUrl,
      expectedSha256: expectedSha256,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'app_update_installer.dart';

Future<void> downloadAndInstallUpdatePlatform({
  required String downloadUrl,
  required String? expectedSha256,
  required UpdateCancellationToken cancellationToken,
  void Function(double progress)? onProgress,
}) async {
  final client = http.Client();
  File? file;
  IOSink? sink;
  const maxUpdateBytes = 150 * 1024 * 1024;
  try {
    final response =
        await client.send(http.Request('GET', Uri.parse(downloadUrl)));
    if (response.statusCode != 200) {
      throw Exception('APK 下载失败：HTTP ${response.statusCode}');
    }

    final directory = await getTemporaryDirectory();
    file = File('${directory.path}/xiaojiuguan_update.apk');
    if (await file.exists()) await file.delete();
    sink = file.openWrite();
    var received = 0;
    final total = response.contentLength ?? -1;
    if (total > maxUpdateBytes) {
      throw Exception('更新包超过 150 MB 限制');
    }
    await for (final chunk in response.stream) {
      if (cancellationToken.isCancelled) {
        throw const UpdateDownloadCancelled();
      }
      received += chunk.length;
      if (received > maxUpdateBytes) {
        throw Exception('更新包超过 150 MB 限制');
      }
      sink.add(chunk);
      onProgress?.call(total > 0 ? received / total : 0);
    }
    await sink.flush();
    await sink.close();
    sink = null;

    if (cancellationToken.isCancelled) throw const UpdateDownloadCancelled();
    if (expectedSha256 == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha256.toLowerCase())) {
      throw Exception('更新包缺少有效 SHA256 校验值');
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
      throw Exception('APK SHA256 校验失败');
    }

    if (cancellationToken.isCancelled) throw const UpdateDownloadCancelled();
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception('无法打开 APK 安装器：${result.message}');
    }
  } catch (_) {
    await sink?.close();
    if (file != null && await file.exists()) await file.delete();
    rethrow;
  } finally {
    client.close();
  }
}

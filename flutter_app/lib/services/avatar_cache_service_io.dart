import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const _cacheExpiry = Duration(days: 7);
const _maxAvatarBytes = 5 * 1024 * 1024;
const _maxCacheBytes = 20 * 1024 * 1024;

Uri? _safeAvatarUri(String source) {
  final uri = Uri.tryParse(source.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.port != 0 && uri.port != 443)) {
    return null;
  }
  return uri;
}

Future<Directory> _cacheDirectory() async {
  final directory = await getApplicationSupportDirectory();
  final cacheDirectory = Directory('${directory.path}/avatar_cache');
  if (!await cacheDirectory.exists()) {
    await cacheDirectory.create(recursive: true);
  }
  return cacheDirectory;
}

Future<File> _avatarFile(String source) async {
  final directory = await _cacheDirectory();
  final key = sha1.convert(source.codeUnits).toString();
  return File('${directory.path}/avatar_cache_$key.img');
}

Future<void> _cleanupCache() async {
  final directory = await _cacheDirectory();
  final now = DateTime.now();
  final files = <File>[];
  var totalBytes = 0;
  await for (final entity in directory.list()) {
    if (entity is! File || !entity.path.contains('avatar_cache_')) continue;
    try {
      final stat = await entity.stat();
      if (now.difference(stat.modified) > _cacheExpiry) {
        await entity.delete();
      } else {
        files.add(entity);
        totalBytes += stat.size;
      }
    } catch (_) {}
  }
  if (totalBytes <= _maxCacheBytes) return;
  files.sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    if (totalBytes <= _maxCacheBytes) break;
    try {
      totalBytes -= (await file.length());
      await file.delete();
    } catch (_) {}
  }
}

Future<Uint8List?> loadCachedAvatar(String source) async {
  if (_safeAvatarUri(source) == null) return null;
  try {
    await _cleanupCache();
    final file = await _avatarFile(source);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    if (DateTime.now().difference(stat.modified) > _cacheExpiry ||
        stat.size > _maxAvatarBytes) {
      await file.delete();
      return null;
    }
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> cacheAvatar(String source) async {
  final uri = _safeAvatarUri(source);
  if (uri == null) return null;
  final client = http.Client();
  try {
    final request = http.Request('GET', uri);
    final response =
        await client.send(request).timeout(const Duration(seconds: 10));
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final contentLength = response.contentLength;
    if (response.statusCode != 200 ||
        !contentType.startsWith('image/') ||
        (contentLength != null && contentLength > _maxAvatarBytes)) {
      await response.stream.drain<void>();
      return null;
    }
    final bytes = <int>[];
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 10))) {
      if (bytes.length + chunk.length > _maxAvatarBytes) return null;
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return null;
    final data = Uint8List.fromList(bytes);
    final file = await _avatarFile(source);
    await file.writeAsBytes(data, flush: true);
    await _cleanupCache();
    return data;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

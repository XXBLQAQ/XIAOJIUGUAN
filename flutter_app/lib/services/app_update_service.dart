import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api_client.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.hasUpdate,
    required this.updateRequired,
    required this.latestVersion,
    required this.versionCode,
    this.minVersion,
    this.minVersionCode,
    this.releaseNotes,
    this.downloadUrl,
    this.sha256,
  });

  final bool hasUpdate;
  final bool updateRequired;
  final String latestVersion;
  final int versionCode;
  final String? minVersion;
  final int? minVersionCode;
  final String? releaseNotes;
  final String? downloadUrl;
  final String? sha256;
}

class AppReleaseLog {
  const AppReleaseLog({
    required this.version,
    required this.versionCode,
    required this.publishedAt,
    required this.content,
  });

  final String version;
  final int versionCode;
  final DateTime publishedAt;
  final String content;

  factory AppReleaseLog.fromJson(Map<String, dynamic> json) {
    return AppReleaseLog(
      version: json['version']?.toString() ?? '',
      versionCode: int.tryParse('${json['version_code']}') ?? 0,
      publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      content: (json['content'] ?? json['release_notes'] ?? '').toString(),
    );
  }
}

class AppUpdateService {
  static const _apiOrigin = 'https://api.xxblqaq.cn';

  bool get supportsApkUpdates =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<List<AppReleaseLog>> getReleaseLogs() async {
    final response =
        await ApiClient().get('/app/releases', authenticated: false, params: {
      'platform': 'android',
      'page': 1,
      'page_size': 50,
    });
    final body = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final raw = body['data'] is Map ? body['data']['items'] : body['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => AppReleaseLog.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<AppUpdateInfo?> check() async {
    if (!supportsApkUpdates) return null;
    final package = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(package.buildNumber) ?? 0;
    final response = await ApiClient().get(
      '/app/version',
      authenticated: false,
      params: {
        'platform': 'android',
        'version': package.version,
        'version_code': currentCode,
      },
    );
    final body = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final raw = body['data'];
    if (raw is! Map) return null;
    final data = Map<String, dynamic>.from(raw);
    final latestCode = int.tryParse('${data['version_code']}') ?? 0;
    final latestVersion = data['latest_version']?.toString() ?? '';
    final serverRequiresUpdate = data['update_required'] == true;
    final forceUpdate = data['is_force'] == true;
    final minVersionCode = int.tryParse('${data['min_version_code']}');
    final belowMinimum = minVersionCode != null && currentCode < minVersionCode;
    final isNewer = latestCode > currentCode ||
        _compareVersions(latestVersion, package.version) > 0;
    final hasUpdate = data['has_update'] == true || isNewer;
    final updateRequired = forceUpdate || belowMinimum || serverRequiresUpdate;
    if (!hasUpdate && !updateRequired) return null;
    return AppUpdateInfo(
      hasUpdate: hasUpdate,
      updateRequired: updateRequired,
      latestVersion: data['latest_version']?.toString() ?? '',
      versionCode: int.tryParse('${data['version_code']}') ?? 0,
      minVersion: data['min_version']?.toString(),
      minVersionCode: int.tryParse('${data['min_version_code']}'),
      releaseNotes: data['release_notes']?.toString(),
      downloadUrl: buildDownloadUrl(data['download_url']?.toString()),
      sha256: _normalizeSha256(data['sha256']),
    );
  }

  String? _normalizeSha256(dynamic value) {
    final hash = value?.toString().trim().toLowerCase();
    return hash != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)
        ? hash
        : null;
  }

  int _compareVersions(String left, String right) {
    final leftParts =
        left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final rightParts =
        right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index++) {
      final leftPart = index < leftParts.length ? leftParts[index] : 0;
      final rightPart = index < rightParts.length ? rightParts[index] : 0;
      if (leftPart != rightPart) return leftPart.compareTo(rightPart);
    }
    return 0;
  }

  String buildDownloadUrl(String? downloadUrl) {
    if (downloadUrl == null || downloadUrl.isEmpty) return '';
    final parsed = Uri.tryParse(downloadUrl);
    if (parsed != null && parsed.hasScheme) {
      if (parsed.scheme != 'https' || parsed.host != 'api.xxblqaq.cn') {
        return '';
      }
      return parsed.toString();
    }
    return '$_apiOrigin${downloadUrl.startsWith('/') ? '' : '/'}$downloadUrl';
  }
}

import 'package:chat_game_app/services/app_update_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateService', () {
    test('仅 Android 原生平台支持 APK 更新', () {
      final service = AppUpdateService();
      expect(
        service.supportsApkUpdates,
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      );
    });

    test('仅允许受信任的 HTTPS 更新地址', () {
      final service = AppUpdateService();

      expect(
        service.buildDownloadUrl('https://api.xxblqaq.cn/download/app.apk'),
        'https://api.xxblqaq.cn/download/app.apk',
      );
      expect(service.buildDownloadUrl('http://api.xxblqaq.cn/app.apk'), '');
      expect(service.buildDownloadUrl('https://example.com/app.apk'), '');
    });
  });
}

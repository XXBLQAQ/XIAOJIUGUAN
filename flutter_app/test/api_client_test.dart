import 'package:chat_game_app/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('允许 HTTPS API 地址', () {
    expect(ApiClient.isAllowedBaseUrl('https://api.example.com/api'), isTrue);
  });

  test('仅允许指定的本地 HTTP 调试地址', () {
    expect(ApiClient.isAllowedBaseUrl('http://localhost:3000/api'), isTrue);
    expect(ApiClient.isAllowedBaseUrl('http://127.0.0.1:3000/api'), isTrue);
    expect(ApiClient.isAllowedBaseUrl('http://10.0.2.2:3000/api'), isTrue);
    expect(ApiClient.isAllowedBaseUrl('http://api.example.com/api'), isFalse);
  });

  test('拒绝缺少主机或使用未知协议的地址', () {
    expect(ApiClient.isAllowedBaseUrl('/api'), isFalse);
    expect(ApiClient.isAllowedBaseUrl('ftp://api.example.com/api'), isFalse);
  });
}

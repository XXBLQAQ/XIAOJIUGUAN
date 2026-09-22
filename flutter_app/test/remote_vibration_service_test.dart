import 'package:chat_game_app/services/remote_vibration_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('远程震动授权缓存按用户隔离', () {
    final firstUserKey = RemoteVibrationService.localPermissionKeyFor('user-a');
    final secondUserKey =
        RemoteVibrationService.localPermissionKeyFor('user-b');

    expect(firstUserKey, isNot(secondUserKey));
    expect(firstUserKey, contains('user-a'));
    expect(secondUserKey, contains('user-b'));
  });
}

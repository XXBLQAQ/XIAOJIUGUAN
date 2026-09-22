import 'package:chat_game_app/services/remote_vibration_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('一分钟内允许前三次震动触发', () {
    final now = DateTime(2026, 1, 1, 12);
    expect(RemoteVibrationPolicy.isWithinLimit([], now), isTrue);
    expect(
      RemoteVibrationPolicy.isWithinLimit([
        now.subtract(const Duration(seconds: 5)),
        now.subtract(const Duration(seconds: 10)),
      ], now),
      isTrue,
    );
  });

  test('一分钟内第四次震动触发应被限制', () {
    final now = DateTime(2026, 1, 1, 12);
    expect(
      RemoteVibrationPolicy.isWithinLimit([
        now.subtract(const Duration(seconds: 5)),
        now.subtract(const Duration(seconds: 10)),
        now.subtract(const Duration(seconds: 15)),
      ], now),
      isFalse,
    );
  });

  test('清理一分钟前的时间戳后允许再次触发', () {
    final now = DateTime(2026, 1, 1, 12);
    final timestamps = [
      now.subtract(const Duration(minutes: 2)),
      now.subtract(const Duration(seconds: 5)),
      now.subtract(const Duration(seconds: 10)),
      now.subtract(const Duration(seconds: 15)),
    ];

    RemoteVibrationPolicy.discardExpired(timestamps, now);

    expect(timestamps, hasLength(3));
    expect(RemoteVibrationPolicy.isWithinLimit(timestamps, now), isFalse);

    timestamps.removeLast();
    expect(RemoteVibrationPolicy.isWithinLimit(timestamps, now), isTrue);
  });
}

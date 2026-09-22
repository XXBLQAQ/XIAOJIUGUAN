class RemoteVibrationPolicy {
  static const maxTriggersPerMinute = 3;
  static const durationMilliseconds = 500;

  static bool isWithinLimit(Iterable<DateTime> timestamps, DateTime now) {
    final cutoff = now.subtract(const Duration(minutes: 1));
    return timestamps.where((time) => time.isAfter(cutoff)).length <
        maxTriggersPerMinute;
  }

  static void discardExpired(List<DateTime> timestamps, DateTime now) {
    final cutoff = now.subtract(const Duration(minutes: 1));
    timestamps.removeWhere((timestamp) => !timestamp.isAfter(cutoff));
  }
}

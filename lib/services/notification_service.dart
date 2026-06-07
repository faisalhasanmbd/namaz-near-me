import 'package:flutter/services.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channel =
      MethodChannel('com.food4u.namaznearme/prayer_alarm');

  // Returns false if native throws PlatformException or returns false (e.g. exact alarm permission denied)
  Future<bool> schedulePrayerReminder({
    required int id,
    required String mosqueName,
    required String namaz,
    required DateTime jamaatTime,
    required int beforeMinutes,
  }) async {
    final target = jamaatTime.subtract(Duration(minutes: beforeMinutes));
    final now = DateTime.now();
    DateTime finalTime = target;

    if (!finalTime.isAfter(now)) {
      if (jamaatTime.isAfter(now)) {
        finalTime = now.add(const Duration(seconds: 5));
      } else {
        finalTime = jamaatTime
            .add(const Duration(days: 1))
            .subtract(Duration(minutes: beforeMinutes));
      }
    }

    try {
      final result = await _channel.invokeMethod<bool>('schedule', {
        'id': id,
        'triggerMs': finalTime.millisecondsSinceEpoch,
        'title': '$namaz — $beforeMinutes min to Jamaat',
        'body': 'Jamaat at $mosqueName is starting soon',
      });
      return result ?? true;
    } on PlatformException {
      return false;
    }
  }

  Future<void> cancelReminder(int id) async {
    await _channel.invokeMethod('cancel', {'id': id});
  }
}

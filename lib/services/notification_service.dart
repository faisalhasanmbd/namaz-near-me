import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _canScheduleExact = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const init = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(init);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _canScheduleExact = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestExactAlarmsPermission() ??
        false;
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  Future<void> schedulePrayerReminder({
    required int id,
    required String mosqueName,
    required String namaz,
    required DateTime jamaatTime,
    required int beforeMinutes,
  }) async {
    await initialize();

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

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'namaz_reminders_v4',
        'Namaz Prayer Reminders',
        channelDescription: 'Alerts before jamaat time — keep as High/Urgent',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    await _plugin.zonedSchedule(
      id,
      '$namaz in $beforeMinutes min',
      'Jamaat at $mosqueName. Prepare for salah.',
      tz.TZDateTime.from(finalTime, tz.local),
      details,
      androidScheduleMode: _canScheduleExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}

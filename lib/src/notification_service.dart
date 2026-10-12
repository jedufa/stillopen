import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as notifications;
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'controller.dart';
import 'models.dart';

class LocalReminderScheduler
    implements ReminderScheduler, ReminderAvailability {
  LocalReminderScheduler({
    notifications.FlutterLocalNotificationsPlugin? plugin,
    this.onNotificationPayload,
  }) : _plugin = plugin ?? notifications.FlutterLocalNotificationsPlugin();

  final notifications.FlutterLocalNotificationsPlugin _plugin;
  final void Function(String?)? onNotificationPayload;
  Future<void>? _initialization;
  bool _permissionsRequested = false;
  static const _settings = MethodChannel('stillopen/notification_settings');
  static const _channelId = 'stillopen_reminders';

  Future<void> initialize() => _initialization ??= _initializePlugin();

  Future<void> _initializePlugin() async {
    tz.initializeTimeZones();
    const android = notifications.AndroidInitializationSettings(
      '@drawable/ic_stat_stillopen',
    );
    const darwin = notifications.DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    try {
      await _plugin.initialize(
        settings: const notifications.InitializationSettings(
          android: android,
          iOS: darwin,
        ),
        onDidReceiveNotificationResponse: (response) =>
            onNotificationPayload?.call(response.payload),
      );
    } on Object {
      _initialization = null;
      rethrow;
    }
  }

  Future<String?> initialNotificationPayload() async {
    await initialize();
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp == true
        ? details?.notificationResponse?.payload
        : null;
  }

  @override
  Future<void> requestPermissions() async {
    await initialize();
    if (_permissionsRequested) return;
    bool? granted;
    if (defaultTargetPlatform == TargetPlatform.android) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            notifications.AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            notifications.IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    // A denial or unavailable implementation must not suppress a later retry
    // after the user changes permissions in system settings.
    _permissionsRequested = granted == true;
  }

  @override
  Future<bool?> notificationsAllowed() async {
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            notifications.AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await android?.areNotificationsEnabled();
      if (enabled != true) return enabled;
      final channels = await android?.getNotificationChannels();
      // App permission alone is insufficient: a user can block just reminders.
      for (final channel
          in channels ?? <notifications.AndroidNotificationChannel>[]) {
        if (channel.id == _channelId &&
            channel.importance == notifications.Importance.none) {
          return false;
        }
      }
      return true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final status = await _plugin
          .resolvePlatformSpecificImplementation<
            notifications.IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return status?.isEnabled;
    }
    return null;
  }

  @override
  Future<void> openNotificationSettings() =>
      _settings.invokeMethod<void>('openNotificationSettings');

  @override
  Future<void> schedule(StillOpenItem item, DateTime when) async {
    await initialize();
    if (await notificationsAllowed() == false) {
      throw const ReminderPermissionDenied();
    }
    await cancel(item.id);
    await _plugin.zonedSchedule(
      id: item.id,
      title: item.title,
      body: 'StillOpen reminder',
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: const notifications.NotificationDetails(
        android: notifications.AndroidNotificationDetails(
          _channelId,
          'StillOpen reminders',
          channelDescription: 'Reminders for StillOpen items',
          importance: notifications.Importance.high,
          priority: notifications.Priority.high,
          icon: '@drawable/ic_stat_stillopen',
        ),
        iOS: notifications.DarwinNotificationDetails(),
      ),
      androidScheduleMode:
          notifications.AndroidScheduleMode.inexactAllowWhileIdle,
      payload: item.id.toString(),
    );
  }

  @override
  Future<void> cancel(int itemId) async {
    await initialize();
    await _plugin.cancel(id: itemId);
  }

  @override
  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }
}

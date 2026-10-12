import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as notifications;
import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/notification_service.dart';

void main() {
  test(
    'UX-05 notification response callback forwards the item payload',
    () async {
      final plugin = _NotificationPlugin();
      final received = <String?>[];
      final scheduler = LocalReminderScheduler(
        plugin: plugin,
        onNotificationPayload: received.add,
      );
      await scheduler.initialize();
      plugin.respond('42');
      expect(received, ['42']);
      await scheduler.initialize();
      expect(plugin.initializeCount, 1);
    },
  );

  test('UX-05 cold notification launch retains its item payload', () async {
    final plugin = _NotificationPlugin()..launchPayload = '57';
    final scheduler = LocalReminderScheduler(plugin: plugin);
    expect(await scheduler.initialNotificationPayload(), '57');
  });
}

class _NotificationPlugin
    implements notifications.FlutterLocalNotificationsPlugin {
  notifications.DidReceiveNotificationResponseCallback? callback;
  int initializeCount = 0;
  String? launchPayload;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool?> initialize({
    required notifications.InitializationSettings settings,
    notifications.DidReceiveNotificationResponseCallback?
    onDidReceiveNotificationResponse,
    notifications.DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCount++;
    callback = onDidReceiveNotificationResponse;
    return true;
  }

  @override
  Future<notifications.NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async =>
      notifications.NotificationAppLaunchDetails(
        launchPayload != null,
        notificationResponse: launchPayload == null
            ? null
            : notifications.NotificationResponse(
                notificationResponseType:
                    notifications.NotificationResponseType.selectedNotification,
                payload: launchPayload,
              ),
      );

  void respond(String payload) => callback?.call(
    notifications.NotificationResponse(
      notificationResponseType:
          notifications.NotificationResponseType.selectedNotification,
      payload: payload,
    ),
  );
}

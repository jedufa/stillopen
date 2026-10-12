import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/models.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

// Exercise the real Flutter adapter and plugin serialization. Only the native
// channel is substituted; these checks do not claim OS delivery evidence.
void main() {
  void contractTest(String name, Future<void> Function() body) =>
      test(name, () => withClock(Clock.fixed(DateTime.utc(2026, 1, 1)), body));
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group(platform.name, () {
      late List<MethodCall> calls;
      late LocalReminderScheduler scheduler;
      bool granted = false;
      bool? allowed = true;
      List<Map<String, Object?>> channels = [];
      String? failMethod;
      Completer<void>? initializationGate;

      setUp(() {
        debugDefaultTargetPlatformOverride = platform;
        if (platform == TargetPlatform.android) {
          AndroidFlutterLocalNotificationsPlugin.registerWith();
        } else {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        }
        calls = [];
        granted = false;
        allowed = true;
        channels = [];
        failMethod = null;
        initializationGate = null;
        scheduler = LocalReminderScheduler();
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == failMethod) {
            throw PlatformException(code: 'synthetic_failure');
          }
          if (call.method == 'initialize') {
            await initializationGate?.future;
            return true;
          }
          if (call.method.startsWith('request')) return granted;
          if (call.method == 'areNotificationsEnabled') return allowed;
          if (call.method == 'getNotificationChannels') return channels;
          if (call.method == 'checkPermissions') {
            return allowed == null ? null : {'isEnabled': allowed};
          }
          if (call.method == 'getNotificationAppLaunchDetails') {
            return {'notificationLaunchedApp': false};
          }
          return null;
        });
      });

      tearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
        tz.setLocalLocation(tz.UTC);
      });

      contractTest(
        'NOTIFY-01 scheduling replaces only the item and preserves instant and payload',
        () async {
          final item = StillOpenItem(
            id: 42,
            title: 'Synthetic reminder',
            state: ItemState.open,
            category: Category.other,
          );
          await scheduler.initialize();
          tz.setLocalLocation(tz.getLocation('Europe/Vienna'));
          final when = DateTime.utc(2030, 3, 31, 7, 5);
          await scheduler.schedule(item, when);
          expect(calls.map((c) => c.method), [
            'initialize',
            if (platform == TargetPlatform.android) ...[
              'areNotificationsEnabled',
              'getNotificationChannels',
            ] else
              'checkPermissions',
            'cancel',
            'zonedSchedule',
          ]);
          expect(
            platform == TargetPlatform.android
                ? (calls.firstWhere((c) => c.method == 'cancel').arguments
                      as Map)['id']
                : calls.firstWhere((c) => c.method == 'cancel').arguments,
            42,
          );
          final scheduled = calls.last.arguments as Map;
          expect(scheduled['id'], 42);
          expect(scheduled['title'], 'Synthetic reminder');
          expect(scheduled['payload'], '42');
          expect(scheduled['body'], 'StillOpen reminder');
          expect(scheduled['timeZoneName'], 'Europe/Vienna');
          expect(scheduled['scheduledDateTime'], '2030-03-31T09:05:00');
          expect(
            DateTime.parse(
              scheduled['scheduledDateTimeISO8601'] as String,
            ).toUtc(),
            when,
          );
          if (platform == TargetPlatform.android) {
            expect(
              (scheduled['platformSpecifics'] as Map)['channelId'],
              'stillopen_reminders',
            );
            expect(
              (scheduled['platformSpecifics'] as Map)['scheduleMode'],
              'inexactAllowWhileIdle',
            );
          } else {
            final init = calls.first.arguments as Map;
            expect(init['requestAlertPermission'], isFalse);
            expect(init['requestSoundPermission'], isFalse);
            expect(init['requestBadgePermission'], isFalse);
          }
          await scheduler.cancel(42);
          await scheduler.cancelAll();
          expect(
            calls.map((c) => c.method).toList().sublist(calls.length - 2),
            ['cancel', 'cancelAll'],
          );
        },
      );

      contractTest(
        'NOTIFY-02 denied permission is retryable and an approved request is not repeated',
        () async {
          final method = platform == TargetPlatform.android
              ? 'requestNotificationsPermission'
              : 'requestPermissions';
          await scheduler.requestPermissions();
          granted = true;
          await scheduler.requestPermissions();
          await scheduler.requestPermissions();
          final requests = calls.where((c) => c.method == method).toList();
          expect(requests, hasLength(2));
          if (platform == TargetPlatform.iOS) {
            expect(requests.last.arguments, containsPair('alert', true));
            expect(requests.last.arguments, containsPair('sound', true));
          }
        },
      );

      contractTest(
        'NOTIFY-08 blocked OS permission prevents false scheduling and is rechecked after settings',
        () async {
          final item = StillOpenItem(
            id: 42,
            title: 'Permission reminder',
            state: ItemState.open,
            category: Category.other,
          );
          allowed = false;
          expect(await scheduler.notificationsAllowed(), isFalse);
          await expectLater(
            scheduler.schedule(item, DateTime.utc(2030)),
            throwsA(isA<ReminderPermissionDenied>()),
          );
          expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
          expect(calls.where((c) => c.method == 'cancel'), isEmpty);
          const settings = MethodChannel('stillopen/notification_settings');
          var settingsOpened = 0;
          messenger.setMockMethodCallHandler(settings, (call) async {
            expect(call.method, 'openNotificationSettings');
            settingsOpened++;
            return null;
          });
          try {
            await scheduler.openNotificationSettings();
            expect(settingsOpened, 1);
          } finally {
            messenger.setMockMethodCallHandler(settings, null);
          }
          allowed = true;
          expect(await scheduler.notificationsAllowed(), isTrue);
          await scheduler.schedule(item, DateTime.utc(2030));
          expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(1));
          allowed = false;
          expect(await scheduler.notificationsAllowed(), isFalse);
          allowed = null;
          expect(await scheduler.notificationsAllowed(), isNull);
        },
      );

      contractTest(
        'NOTIFY-09 channel blocking is distinguished from whole-app permission',
        () async {
          Map<String, Object?> channelInfo(String id, int importance) => {
            'id': id,
            'name': id,
            'description': 'Synthetic channel',
            'importance': importance,
            'showBadge': true,
            'bypassDnd': false,
            'playSound': true,
            'enableLights': false,
            'enableVibration': true,
            'ledColor': 0,
            'audioAttributesUsage': 5,
          };
          if (platform == TargetPlatform.android) {
            channels = [
              channelInfo('other', 0),
              channelInfo('stillopen_reminders', 4),
            ];
            expect(await scheduler.notificationsAllowed(), isTrue);
            channels = [channelInfo('stillopen_reminders', 0)];
            expect(await scheduler.notificationsAllowed(), isFalse);
            channels = [];
            expect(await scheduler.notificationsAllowed(), isTrue);
          } else {
            allowed = true;
            expect(await scheduler.notificationsAllowed(), isTrue);
            allowed = false;
            expect(await scheduler.notificationsAllowed(), isFalse);
          }
        },
      );

      contractTest(
        'NOTIFY-03 concurrent initialization registers once and native errors allow retry',
        () async {
          initializationGate = Completer<void>();
          final first = scheduler.initialize();
          final second = scheduler.initialize();
          await Future<void>.delayed(Duration.zero);
          expect(calls.where((c) => c.method == 'initialize'), hasLength(1));
          initializationGate!.complete();
          await Future.wait([first, second]);
          scheduler = LocalReminderScheduler();
          failMethod = 'initialize';
          await expectLater(
            scheduler.initialize(),
            throwsA(isA<PlatformException>()),
          );
          failMethod = null;
          await scheduler.initialize();
          expect(calls.where((c) => c.method == 'initialize'), hasLength(3));
        },
      );

      contractTest(
        'NOTIFY-04 cancellation and scheduling failures are not reported as success',
        () async {
          final item = StillOpenItem(
            id: 7,
            title: 'Synthetic',
            state: ItemState.open,
            category: Category.other,
          );
          failMethod = 'cancel';
          await expectLater(
            scheduler.schedule(item, DateTime.utc(2030)),
            throwsA(isA<PlatformException>()),
          );
          expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
          failMethod = 'zonedSchedule';
          await expectLater(
            scheduler.schedule(item, DateTime.utc(2030)),
            throwsA(isA<PlatformException>()),
          );
          failMethod = null;
          await scheduler.schedule(item, DateTime.utc(2030));
          expect(await scheduler.initialNotificationPayload(), isNull);
        },
      );
    });
  }
}

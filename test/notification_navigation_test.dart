import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:stillopen/main.dart';
import 'package:stillopen/src/controller.dart';

import 'support/contract_fakes.dart';

void main() {
  testWidgets('NOTIFY-05 cold launch opens the addressed item after loading', (
    tester,
  ) async {
    final controller = StillOpenController(store: MemoryContractStore());
    await controller.load();
    await controller.quickAdd(title: 'Synthetic notification target');
    final plugin = _NavigationPlugin()
      ..payload = controller.items.single.id.toString();
    await tester.pumpWidget(
      StillOpenApp(
        controller: controller,
        notificationPlugin: plugin,
        incomingShareSource: _EmptyShares(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Mark Done'), findsOneWidget);
    expect(find.text('Synthetic notification target'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'NOTIFY-06 warm tap selects the correct item and stale payloads do nothing',
    (tester) async {
      final controller = StillOpenController(store: MemoryContractStore());
      await controller.load();
      await controller.quickAdd(title: 'Synthetic notification target');
      final id = controller.items.single.id;
      await controller.markDone(controller.items.single);
      await controller.quickAdd(title: 'Unrelated open item');
      final plugin = _NavigationPlugin();
      await tester.pumpWidget(
        StillOpenApp(
          controller: controller,
          notificationPlugin: plugin,
          incomingShareSource: _EmptyShares(),
        ),
      );
      await tester.pumpAndSettle();
      for (final payload in ['', 'not-an-id', '-9']) {
        plugin.respond(payload);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      }
      plugin.respond('$id');
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Reopen'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      plugin.respond('$id');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'NOTIFY-07 item deleted during launch lookup does not open stale details',
    (tester) async {
      final controller = StillOpenController(store: MemoryContractStore());
      await controller.load();
      await controller.quickAdd(title: 'Deleted notification target');
      final id = controller.items.single.id;
      final plugin = _NavigationPlugin()
        ..payload = '$id'
        ..launchGate = Completer<void>();
      await tester.pumpWidget(
        StillOpenApp(
          controller: controller,
          notificationPlugin: plugin,
          incomingShareSource: _EmptyShares(),
        ),
      );
      await tester.pump();
      await controller.deleteItem(controller.items.single);
      plugin.launchGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _NavigationPlugin implements FlutterLocalNotificationsPlugin {
  String? payload;
  Completer<void>? launchGate;
  DidReceiveNotificationResponseCallback? callback;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    callback = onDidReceiveNotificationResponse;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    await launchGate?.future;
    return NotificationAppLaunchDetails(
      payload != null,
      notificationResponse: payload == null ? null : _response(payload),
    );
  }

  NotificationResponse _response(String? payload) => NotificationResponse(
    notificationResponseType: NotificationResponseType.selectedNotification,
    payload: payload,
  );
  void respond(String payload) => callback?.call(_response(payload));
}

class _EmptyShares implements IncomingShareSource {
  @override
  Future<List<SharedMediaFile>> getInitialMedia() async => [];
  @override
  Future<List<IncomingShareExtra>> getInitialExtras() async => [];
  @override
  Stream<List<SharedMediaFile>> getMediaStream() => const Stream.empty();
  @override
  Stream<List<IncomingShareExtra>> getExtraStream() => const Stream.empty();
  @override
  Future<void> reset() async {}
}

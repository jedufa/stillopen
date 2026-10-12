import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:stillopen/main.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/attachment_paths.dart';
import 'package:stillopen/src/models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'DEVICE-STORE-02 a separate app process reads migrated graph proof and settings',
    (tester) async {
      if (!const bool.fromEnvironment('STILLOPEN_DISPOSABLE_DEVICE')) {
        throw StateError(
          'Run only through the explicitly targeted disposable-device suite',
        );
      }
      // This target is installed and launched separately, after a force-stop.
      // No SharedPreferences mock, shared Dart map or controller instance survives.
      final controller = StillOpenController(
        store: SharedPreferencesStillOpenStore(),
        attachmentDirectoryProvider: applicationAttachmentDirectory,
      );
      await controller.load();
      expect(controller.items.single.id, 501);
      expect(controller.items.single.title, 'Edited after native upgrade');
      expect(
        controller.items.single.reminderAt,
        DateTime(2027, 6, 4, 9, 5).millisecondsSinceEpoch,
      );
      expect(controller.attachments.single.itemId, 501);
      expect(
        File(controller.attachments.single.uri).readAsStringSync(),
        'proof A\n',
      );
      expect(controller.themePreference, AppThemePreference.dark);
      expect(controller.notificationsEnabled, isFalse);
      expect(controller.defaultReminderMinute, 5);
      expect(controller.showTemplateShortcuts, isFalse);
      controller.dispose();
    },
  );

  testWidgets(
    'DEVICE-ATTACHMENT-01 item attachment opens with actual DOCX and ZIP MIME',
    (tester) async {
      if (!const bool.fromEnvironment('STILLOPEN_DISPOSABLE_DEVICE')) {
        throw StateError(
          'Run only through the explicitly targeted disposable-device suite',
        );
      }
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw StateError('This test requires the native OpenFilex channel');
      }
      final files = Directory.systemTemp.createTempSync('stillopen-mime-test-');
      final controller = StillOpenController(
        store: _AttachmentTestStore(),
        attachmentDirectoryProvider: () async =>
            Directory('${files.path}/owned'),
      );
      const channel = MethodChannel('open_file');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return '{"type":0,"message":"done"}';
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        controller.dispose();
        files.deleteSync(recursive: true);
      });
      await controller.load();
      await controller.quickAdd(title: 'Native attachment dispatch');
      final item = controller.selectedItem!;
      for (final extension in ['docx', 'zip']) {
        final file = File('${files.path}/document.$extension')
          ..writeAsStringSync('Synthetic $extension attachment bytes');
        await controller.addAttachment(
          item: item,
          uri: file.path,
          label: 'document.$extension',
          sourceType: SourceType.manual,
        );
      }
      await tester.pumpWidget(
        StillOpenApp(
          controller: controller,
          incomingShareSource: const _EmptyAttachmentShares(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(item.title));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Attachments'));
      await tester.tap(find.text('Attachments'));
      await tester.pumpAndSettle();
      for (final attachment in controller.attachments) {
        final row = find
            .ancestor(
              of: find.text(attachment.label),
              matching: find.byType(Material),
            )
            .first;
        final button = find.descendant(
          of: row,
          matching: find.byTooltip('Open attachment'),
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        final call = calls.last;
        expect(call.method, 'open_file');
        final arguments = call.arguments as Map;
        expect(arguments['file_path'], attachment.uri);
        expect(File(arguments['file_path'] as String).existsSync(), isTrue);
        expect(
          arguments['type'],
          attachment.label.endsWith('.docx')
              ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
              : 'application/zip',
        );
        expect(arguments['type'], isNot('application/pdf'));
        expect(arguments['type'], isNot('text/plain'));
      }
      expect(calls, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _AttachmentTestStore implements StillOpenStore {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

class _EmptyAttachmentShares implements IncomingShareSource {
  const _EmptyAttachmentShares();
  @override
  Stream<List<SharedMediaFile>> getMediaStream() => const Stream.empty();
  @override
  Future<List<SharedMediaFile>> getInitialMedia() async => [];
  @override
  Stream<List<IncomingShareExtra>> getExtraStream() => const Stream.empty();
  @override
  Future<List<IncomingShareExtra>> getInitialExtras() async => [];
  @override
  Future<void> reset() async {}
}

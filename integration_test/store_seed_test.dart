import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/attachment_paths.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'DEVICE-STORE-01 native legacy preferences migrate with proof bytes',
    (tester) async {
      if (!const bool.fromEnvironment('STILLOPEN_DISPOSABLE_DEVICE')) {
        throw StateError(
          'Run only through the explicitly targeted disposable-device suite',
        );
      }
      final store = SharedPreferencesStillOpenStore();
      for (final key in [
        'stillopen_snapshot_v2',
        'stillopen_items_v1',
        'stillopen_attachments_v1',
        'stillopen_settings_v1',
      ]) {
        expect(
          await store.getString(key),
          isNull,
          reason: 'Refuse to overwrite existing app data',
        );
      }
      final documents = await getApplicationDocumentsDirectory();
      final proofs = Directory('${documents.path}/attachments')
        ..createSync(recursive: true);
      final proof = File('${proofs.path}/historical.txt')
        ..writeAsStringSync('proof A\n', flush: true);
      final raw = utf8.decode(
        base64Decode(const String.fromEnvironment('STILLOPEN_LEGACY_FIXTURE')),
      );
      final fixture =
          jsonDecode(raw.replaceAll('@LOCAL_PROOF@', proof.path)) as Map;
      for (final section in ['items', 'attachments', 'settings']) {
        await store.setString(
          'stillopen_${section}_v1',
          jsonEncode(fixture[section]),
        );
      }
      final controller = StillOpenController(
        store: store,
        attachmentDirectoryProvider: applicationAttachmentDirectory,
      );
      await controller.load();
      expect(controller.items.single.id, 501);
      await controller.renameItem(
        controller.items.single,
        'Edited after native upgrade',
      );
      expect(await store.getString('stillopen_snapshot_v2'), isNotNull);
      controller.dispose();
    },
  );
}

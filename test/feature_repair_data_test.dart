import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/incoming_share/incoming_share_ingestor.dart';
import 'package:stillopen/src/incoming_share/ios_pending_share_store.dart';
import 'package:stillopen/src/models.dart';
import 'package:stillopen/src/rules.dart';

import 'support/contract_fakes.dart';

void main() {
  late Directory sandbox;
  late Directory attachments;
  late MemoryContractStore store;
  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('stillopen-feature-repair-');
    attachments = Directory('${sandbox.path}/attachments');
    store = MemoryContractStore();
  });
  tearDown(() => sandbox.deleteSync(recursive: true));

  StillOpenController fresh({ReminderScheduler? reminders}) {
    final controller = StillOpenController(
      store: store,
      attachmentDirectoryProvider: () async => attachments,
      reminderScheduler: reminders,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test(
    'REPAIR-DATA-01 background share and quick add serialize through durable save',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final source = File('${sandbox.path}/proof.pdf')
        ..writeAsStringSync('proof');
      final controller = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          return attachments;
        },
      );
      addTearDown(controller.dispose);
      await controller.load();
      final capture = controller.addSharedFiles([
        IncomingSharedFile(path: source.path),
      ]);
      await entered.future;
      final add = controller.quickAdd(title: 'Created while copying');
      release.complete();
      await Future.wait([capture, add]);
      final restarted = fresh();
      await restarted.load();
      expect(restarted.items.map((item) => item.id).toSet(), hasLength(2));
      expect(
        File(restarted.attachments.single.uri).readAsStringSync(),
        'proof',
      );
      expect(
        restarted.items.any(
          (item) => item.id == restarted.attachments.single.itemId,
        ),
        isTrue,
      );
    },
  );

  test(
    'REPAIR-DATA-01 delete during attachment copy leaves no orphan after restart',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final source = File('${sandbox.path}/proof.pdf')
        ..writeAsStringSync('proof');
      final controller = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          return attachments;
        },
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.quickAdd(title: 'Deleted during copy');
      final item = controller.items.single;
      final attach = controller.addAttachment(
        item: item,
        uri: source.path,
        label: 'Proof',
        sourceType: SourceType.pdf,
      );
      await entered.future;
      final remove = controller.deleteItem(item);
      release.complete();
      await Future.wait([attach, remove]);
      final restarted = fresh();
      await restarted.load();
      expect(restarted.items, isEmpty);
      expect(restarted.attachments, isEmpty);
      expect(attachments.listSync().whereType<File>(), isEmpty);
    },
  );

  test('REPAIR-DATA-01 queued stale item edits retain both changes', () async {
    final controller = fresh();
    await controller.load();
    await controller.quickAdd(title: 'Original');
    final old = controller.items.single;
    await Future.wait([
      controller.renameItem(old, 'Renamed'),
      controller.setNote(old, 'New context'),
    ]);
    final restarted = fresh();
    await restarted.load();
    expect(restarted.items.single.title, 'Renamed');
    expect(restarted.items.single.notes, 'New context');
  });

  test(
    'REPAIR-DATA-02 partial share preserves unavailable proof and retry restores same item',
    () async {
      final controller = fresh();
      await controller.load();
      final first = File('${sandbox.path}/first.pdf')
        ..writeAsStringSync('first proof');
      final second = File('${sandbox.path}/second.pdf');
      final files = [
        IncomingSharedFile(path: first.path),
        IncomingSharedFile(path: second.path),
      ];
      expect(
        await controller.addSharedContent(files: files, eventId: 'partial'),
        isTrue,
      );
      final id = controller.items.single.id;
      expect(controller.attachments, hasLength(2));
      expect(controller.lastCaptureReport!.filesUnavailable, 1);
      expect(
        controller.snackbarMessage,
        contains('1 attachment(s) unavailable'),
      );
      second.writeAsStringSync('second proof');
      await controller.addSharedContent(files: files, eventId: 'partial');
      expect(controller.items.single.id, id);
      expect(controller.lastCaptureReport!.complete, isTrue);
      expect(
        controller.attachments
            .map((a) => File(a.uri).readAsStringSync())
            .toSet(),
        {'first proof', 'second proof'},
      );
      final restarted = fresh();
      await restarted.load();
      expect(
        await restarted.addSharedContent(files: files, eventId: 'partial'),
        isFalse,
      );
      expect(restarted.items, hasLength(1));
    },
  );

  test(
    'REPAIR-DATA-02 text capture with missing file retains a visible attachment gap',
    () async {
      final controller = fresh();
      await controller.load();
      await controller.addSharedContent(
        text: 'Receipt attached',
        files: [IncomingSharedFile(path: '${sandbox.path}/missing.pdf')],
      );
      expect(controller.items.single.notes, 'Receipt attached');
      expect(
        controller.attachments.single.uri,
        startsWith('stillopen-metadata-only:'),
      );
      expect(controller.snackbarMessage, contains('unavailable'));
    },
  );

  test(
    'REPAIR-DATA-03 valid iOS manifest survives transient storage failure and retries after restart',
    () async {
      final queue = Directory('${sandbox.path}/queue/pending_shares')
        ..createSync(recursive: true);
      final pending = File('${queue.path}/event.json')
        ..writeAsStringSync(
          jsonEncode({
            'id': 'retry-event',
            'createdAt': 1,
            'text': 'Retry me',
            'files': [],
          }),
        );
      final controller = fresh();
      await controller.load();
      final ingest = IncomingShareIngestor(
        controller: controller,
        store: DirectoryPendingShareStore(queue.parent),
      );
      store.failNextWrite = true;
      expect(await ingest.ingestPendingShares(), 0);
      expect(pending.existsSync(), isTrue);
      final restarted = fresh();
      await restarted.load();
      expect(
        await IncomingShareIngestor(
          controller: restarted,
          store: DirectoryPendingShareStore(queue.parent),
        ).ingestPendingShares(),
        1,
      );
      expect(restarted.items.single.title, 'Retry me');
      expect(pending.existsSync(), isFalse);
    },
  );

  test(
    'REPAIR-DATA-02 iOS partial capture retains original files until all proof is durable',
    () async {
      final root = Directory('${sandbox.path}/queue')..createSync();
      final queue = Directory('${root.path}/pending_shares')..createSync();
      final first = File('${root.path}/first.pdf')..writeAsStringSync('first');
      final missing = File('${root.path}/second.pdf');
      final manifest = File('${queue.path}/event.json')
        ..writeAsStringSync(
          jsonEncode({
            'id': 'partial-event',
            'createdAt': 1,
            'text': 'Two receipts',
            'files': [
              for (final file in [first, missing])
                {
                  'path': file.path,
                  'originalName': file.uri.pathSegments.last,
                  'available': true,
                },
            ],
          }),
        );
      final controller = fresh();
      await controller.load();
      final ingestor = IncomingShareIngestor(
        controller: controller,
        store: DirectoryPendingShareStore(root),
      );
      await ingestor.ingestPendingShares();
      expect(manifest.existsSync(), isTrue);
      expect(first.existsSync(), isTrue);
      missing.writeAsStringSync('second');
      await ingestor.ingestPendingShares();
      expect(controller.items, hasLength(1));
      expect(
        controller.attachments
            .map((a) => File(a.uri).readAsStringSync())
            .toSet(),
        {'first', 'second'},
      );
      expect(manifest.existsSync(), isFalse);
      expect(first.existsSync(), isFalse);
    },
  );

  test(
    'REPAIR-QUEUE-01 malformed native field types are quarantined while valid neighboring capture ingests',
    () async {
      final root = Directory('${sandbox.path}/native-queue')..createSync();
      final pending = Directory('${root.path}/pending_shares')..createSync();
      final malformed = [
        {'id': 123, 'text': 'Invalid numeric id'},
        {'id': 'bad-files', 'text': 'Invalid file list', 'files': 'not-a-list'},
        {'id': 'bad-text', 'text': false},
      ];
      for (var i = 0; i < malformed.length; i++) {
        File(
          '${pending.path}/bad-$i.json',
        ).writeAsStringSync(jsonEncode(malformed[i]));
      }
      File('${pending.path}/valid.json').writeAsStringSync(
        jsonEncode({
          'id': 'valid-neighbor',
          'text': 'Recover valid neighbor',
          'createdAt': 1,
        }),
      );
      final controller = fresh();
      await controller.load();
      final ingestor = IncomingShareIngestor(
        controller: controller,
        store: DirectoryPendingShareStore(root),
      );
      expect(await ingestor.ingestPendingShares(), 1);
      expect(controller.items.single.title, 'Recover valid neighbor');
      expect(
        Directory('${root.path}/failed_shares').listSync().whereType<File>(),
        hasLength(3),
      );
      expect(pending.listSync(), isEmpty);
    },
  );

  test(
    'REPAIR-QUEUE-02 acknowledgement is idempotent after provider file is already gone',
    () async {
      final root = Directory('${sandbox.path}/expired-provider')..createSync();
      final pending = Directory('${root.path}/pending_shares')..createSync();
      final source = File('${root.path}/proof.pdf')
        ..writeAsStringSync('temporary provider proof');
      final manifest = File('${pending.path}/event.json')
        ..writeAsStringSync(
          jsonEncode({
            'id': 'expired-file',
            'text': 'Already durable capture',
            'files': [
              {'path': source.path},
            ],
          }),
        );
      final queue = DirectoryPendingShareStore(root);
      final event = (await queue.listPendingManifests()).single;
      source.deleteSync();
      await queue.markProcessed(event);
      expect(manifest.existsSync(), isFalse);
      await queue.markProcessed(event);
      expect(await queue.listPendingManifests(), isEmpty);
    },
  );

  test(
    'REPAIR-QUEUE-03 explicitly unavailable native proof is acknowledged once with its warning and placeholder intact',
    () async {
      final root = Directory('${sandbox.path}/unavailable-provider')
        ..createSync();
      final pending = Directory('${root.path}/pending_shares')..createSync();
      final manifest = File('${pending.path}/event.json')
        ..writeAsStringSync(
          jsonEncode({
            'id': 'unavailable-proof',
            'text': 'Provider could not supply proof',
            'files': [
              {'path': '', 'originalName': 'receipt.pdf', 'available': false},
            ],
          }),
        );
      final controller = fresh();
      await controller.load();
      final ingestor = IncomingShareIngestor(
        controller: controller,
        store: DirectoryPendingShareStore(root),
      );
      expect(await ingestor.ingestPendingShares(), 1);
      expect(
        controller.attachments.single.uri,
        startsWith('stillopen-metadata-only:'),
      );
      expect(controller.snackbarMessage, contains('unavailable'));
      expect(controller.lastCaptureReport!.filesUnavailable, 1);
      expect(controller.lastCaptureReport!.retryableFiles, 0);
      expect(manifest.existsSync(), isFalse);
      final committed = store.values['stillopen_snapshot_v2'];
      expect(await ingestor.ingestPendingShares(), 0);
      expect(store.values['stillopen_snapshot_v2'], committed);
      expect(controller.items, hasLength(1));
      expect(controller.attachments, hasLength(1));
    },
  );

  test(
    'REPAIR-DATA-04 explicit share events and deleted-content recapture are distinct',
    () async {
      final controller = fresh();
      await controller.load();
      const url = 'https://example.com/follow-up';
      await controller.addSharedText(url, isUrl: true);
      await controller.deleteItem(controller.items.single);
      await controller.quickAdd(
        title: 'Unrelated item reuses deleted identity',
      );
      expect(await controller.addSharedText(url, isUrl: true), isTrue);
      await controller.addSharedContent(
        text: url,
        isUrl: true,
        eventId: 'new-explicit-share',
      );
      expect(controller.items, hasLength(3));
      expect(
        await controller.addSharedContent(
          text: url,
          isUrl: true,
          eventId: 'new-explicit-share',
        ),
        isFalse,
      );
    },
  );

  test(
    'REPAIR-DATE-01 template deadline stays anchored through edits, clock advance and reload',
    () async {
      var now = DateTime(2030, 1, 1, 10);
      await withClock(Clock(() => now), () async {
        final controller = fresh();
        await controller.load();
        await controller.createFromTemplate(TemplateType.school);
        final due = controller.items.single.dueAt;
        expect(due, DateTime(2030, 1, 2, 20).millisecondsSinceEpoch);
        now = DateTime(2030, 1, 3, 10);
        await controller.renameItem(controller.items.single, 'Signed form');
        final restarted = fresh();
        await restarted.load();
        expect(restarted.items.single.dueAt, due);
        expect(minimalStatusSentence(restarted.items.single), 'Overdue');
      });
    },
  );

  test(
    'REPAIR-DATE-02 terminal one-time long-term Done cancels after editing its reminder',
    () async {
      await withClock(Clock.fixed(DateTime(2030, 1, 1, 10)), () async {
        final reminders = RecordingReminders();
        final controller = fresh(reminders: reminders);
        await controller.load();
        await controller.createFromTemplate(TemplateType.longTerm);
        await controller.setRecurrenceHint(controller.items.single, '');
        await controller.setPickedReminder(
          controller.items.single,
          DateTime(2030, 2, 1),
        );
        await controller.markDone(controller.items.single);
        expect(reminders.scheduled, isEmpty);
        expect(controller.items.single.nextCycleAtEpoch, isNull);
        final restarted = fresh(reminders: reminders);
        await restarted.load();
        expect(reminders.scheduled, isEmpty);
      });
    },
  );

  test(
    'REPAIR-DATE-04 waiting start survives unrelated edit, restart and backup',
    () async {
      var now = DateTime(2030, 1, 1, 10);
      await withClock(Clock(() => now), () async {
        final controller = fresh();
        await controller.load();
        await controller.quickAdd(title: 'Await response');
        await controller.setWaitingOn(controller.items.single, 'Provider');
        final start = controller.items.single.waitingSinceAt;
        now = DateTime(2030, 4, 1, 10);
        await controller.setNote(controller.items.single, 'Still waiting');
        final restarted = fresh();
        await restarted.load();
        expect(restarted.items.single.waitingSinceAt, start);
        expect(waitingTooLong(restarted.items.single), isTrue);
        await restarted.setWaitingOn(restarted.items.single, '');
        expect(restarted.items.single.waitingSinceAt, isNull);
      });
    },
  );

  test(
    'REPAIR-UI-03 note body search and new-item filters retain findability',
    () async {
      final controller = fresh();
      await controller.load();
      controller.selectDomainFilter(DomainFilter.medical);
      controller.selectPersonFilter(PersonFilter.partner);
      await controller.quickAdd(title: 'Buy stationery');
      expect(controller.visibleItems, hasLength(1));
      await controller.addNoteAttachment(
        controller.items.single,
        'Receipt\nHidden reference 8675309',
      );
      controller.setQuery('8675309');
      expect(controller.visibleItems.single.title, 'Buy stationery');
    },
  );

  test(
    'REPAIR-UI-04 threshold persists and draft uses selected default preset',
    () async {
      await withClock(Clock.fixed(DateTime(2030, 1, 1, 10)), () async {
        final controller = fresh();
        await controller.load();
        await controller.cycleFarFutureThreshold();
        await controller.setDefaultReminder('Next week', 9, 15);
        final restarted = fresh();
        await restarted.load();
        expect(restarted.farFutureThreshold, FarFutureThreshold.threeMonths);
        await restarted.createFromTemplate(TemplateType.document);
        expect(restarted.selectedTab, HomeTab.draft);
        expect(
          restarted.items.single.reminderAt,
          DateTime(2030, 1, 8, 9, 15).millisecondsSinceEpoch,
        );
      });
    },
  );

  test(
    'REPAIR-UI-05 lifecycle history retains completion and reopening across backup import',
    () async {
      var now = DateTime(2030, 1, 1, 10);
      await withClock(Clock(() => now), () async {
        final controller = fresh();
        await controller.load();
        await controller.quickAdd(title: 'Keep event history');
        now = DateTime(2030, 1, 2, 11);
        await controller.markDone(controller.items.single);
        now = DateTime(2030, 1, 3, 12);
        await controller.reopen(controller.items.single);
        final backup = controller.exportBackupJson();
        await controller.importBackupJson(backup, replace: true);
        final restarted = fresh();
        await restarted.load();
        restarted.openDetails(restarted.items.single.id);
        final events = restarted.selectedDetails!.timeline;
        expect(
          events.every((event) => event.itemId == restarted.items.single.id),
          isTrue,
        );
        expect(events.map((e) => e.label), [
          'Created in StillOpen',
          'Moved to Done',
          'Reopened',
        ]);
        expect(events.map((e) => e.createdAt), [
          DateTime(2030, 1, 1, 10).millisecondsSinceEpoch,
          DateTime(2030, 1, 2, 11).millisecondsSinceEpoch,
          DateTime(2030, 1, 3, 12).millisecondsSinceEpoch,
        ]);
      });
    },
  );

  test(
    'REPAIR-NOTIFY-01 denied permission is visible and granting it on resume schedules saved reminder',
    () async {
      await withClock(Clock.fixed(DateTime(2030, 1, 1, 8)), () async {
        final reminders = PermissionReminders();
        final controller = fresh(reminders: reminders);
        await controller.load();
        await controller.quickAdd(title: 'Blocked future reminder');
        await controller.setPickedReminder(
          controller.items.single,
          DateTime(2030, 1, 2),
          hour: 9,
          minute: 0,
        );
        expect(controller.notificationPermissionGranted, isFalse);
        expect(
          controller.snackbarMessage,
          contains('blocked in device settings'),
        );
        expect(reminders.scheduled, isEmpty);
        await controller.setNotificationsEnabled(false);
        await controller.setNotificationsEnabled(true);
        expect(controller.notificationsEnabled, isTrue);
        expect(controller.notificationPermissionGranted, isFalse);
        final promptsBeforeResume = reminders.requests;
        reminders.allowed = true;
        await controller.reconcileNotifications();
        expect(reminders.requests, promptsBeforeResume);
        expect(controller.notificationPermissionGranted, isTrue);
        expect(reminders.scheduled.values.single, DateTime(2030, 1, 2, 9));
      });
    },
  );

  test(
    'REPAIR-NOTIFY-02 elapsed pending alarm survives cold load and unrelated edit but explicit removal cancels',
    () async {
      var now = DateTime(2030, 1, 1, 8);
      await withClock(Clock(() => now), () async {
        final reminders = RecordingReminders();
        final controller = fresh(reminders: reminders);
        await controller.load();
        await controller.quickAdd(title: 'Delayed alarm');
        await controller.setPickedReminder(
          controller.items.single,
          now,
          hour: 9,
          minute: 0,
        );
        now = DateTime(2030, 1, 1, 9, 1);
        final restarted = fresh(reminders: reminders);
        await restarted.load();
        expect(reminders.scheduled.values.single, DateTime(2030, 1, 1, 9));
        await restarted.renameItem(
          restarted.items.single,
          'Still pending after rename',
        );
        expect(reminders.scheduled, hasLength(1));
        await restarted.reconcileNotifications();
        expect(reminders.scheduled, hasLength(1));
        await restarted.clearReminder(restarted.items.single);
        expect(reminders.scheduled, isEmpty);
      });
    },
  );

  test(
    'REPAIR-NOTIFY-03 replacing future alarm with past Today cancels it and reports passed date',
    () async {
      await withClock(Clock.fixed(DateTime(2030, 1, 1, 21)), () async {
        final reminders = RecordingReminders();
        final controller = fresh(reminders: reminders);
        await controller.load();
        await controller.quickAdd(title: 'Evening shortcut');
        await controller.setReminderTomorrow(controller.items.single);
        expect(reminders.scheduled, hasLength(1));
        await controller.setReminderToday(controller.items.single);
        expect(reminders.scheduled, isEmpty);
        expect(
          controller.snackbarMessage,
          'Saved, but reminder date has passed.',
        );
        await controller.setReminderTomorrow(controller.items.single);
        await controller.markDone(controller.items.single);
        expect(reminders.scheduled, isEmpty);
      });
    },
  );

  test(
    'REPAIR-NOTIFY-04 late Done cancellation reconciles a subsequent committed reopen',
    () async {
      await withClock(Clock.fixed(DateTime(2030, 1, 1, 8)), () async {
        final reminders = GatedReminders();
        final controller = fresh(reminders: reminders);
        await controller.load();
        await controller.quickAdd(title: 'Reopen during cancellation');
        await controller.setReminderTomorrow(controller.items.single);
        final gate = OperationGate();
        reminders.cancelGate = gate;
        final done = controller.markDone(controller.items.single);
        await gate.started.future;
        await controller.reopen(controller.items.single);
        expect(reminders.scheduled, hasLength(1));
        gate.release.complete();
        await done;
        expect(controller.items.single.state, ItemState.open);
        expect(reminders.scheduled.values.single, DateTime(2030, 1, 2, 20));
      });
    },
  );

  test(
    'REPAIR-NOTIFY-04 late disable cancellation reconciles subsequently enabled reminders',
    () async {
      await withClock(Clock.fixed(DateTime(2030, 1, 1, 8)), () async {
        final reminders = GatedReminders();
        final controller = fresh(reminders: reminders);
        await controller.load();
        await controller.quickAdd(title: 'Enable during cancellation');
        await controller.setReminderTomorrow(controller.items.single);
        final gate = OperationGate();
        reminders.cancelAllGate = gate;
        final disable = controller.setNotificationsEnabled(false);
        await gate.started.future;
        await controller.setNotificationsEnabled(true);
        gate.release.complete();
        await disable;
        expect(controller.notificationsEnabled, isTrue);
        expect(reminders.scheduled.values.single, DateTime(2030, 1, 2, 20));
      });
    },
  );

  test(
    'REPAIR-NOTIFY-05 delayed scheduling never adopts a reminder whose store write later fails',
    () async {
      await withClock(Clock.fixed(DateTime(2030, 1, 1, 8)), () async {
        final failingStore = GatedFailStore();
        final reminders = GatedReminders();
        final controller = StillOpenController(
          store: failingStore,
          reminderScheduler: reminders,
        );
        addTearDown(controller.dispose);
        await controller.load();
        await controller.quickAdd(
          title: 'Only committed reminder may schedule',
        );
        final schedule = OperationGate();
        reminders.scheduleGate = schedule;
        final first = controller.setPickedReminder(
          controller.items.single,
          DateTime(2030, 1, 2),
        );
        await schedule.started.future;
        final write = OperationGate();
        failingStore.failGate = write;
        final second = controller.setPickedReminder(
          controller.items.single,
          DateTime(2030, 1, 3),
        );
        final rejected = expectLater(
          second,
          throwsA(isA<FileSystemException>()),
        );
        await write.started.future;
        schedule.release.complete();
        await first;
        expect(reminders.scheduled.values.single, DateTime(2030, 1, 2, 20));
        write.release.complete();
        await rejected;
        expect(
          controller.items.single.reminderAt,
          DateTime(2030, 1, 2, 20).millisecondsSinceEpoch,
        );
        expect(reminders.scheduled.values.single, DateTime(2030, 1, 2, 20));
        expect(reminders.scheduleAttempts, [DateTime(2030, 1, 2, 20)]);
      });
    },
  );

  test(
    'REPAIR-DATA-05 attachment MIME survives backup and legacy extension inference',
    () async {
      final controller = fresh();
      await controller.load();
      final file = File('${sandbox.path}/contract.docx')
        ..writeAsStringSync('document bytes');
      await controller.addSharedFiles([
        IncomingSharedFile(
          path: file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
      ]);
      await controller.importBackupJson(
        controller.exportBackupJson(),
        replace: true,
      );
      final restarted = fresh();
      await restarted.load();
      expect(
        restarted.attachmentMimeType(restarted.attachments.single),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(
        restarted.attachmentMimeType(
          const ItemAttachment(
            itemId: 1,
            uri: '/saved/receipt.png',
            label: 'Receipt',
            sourceType: SourceType.pdf,
          ),
        ),
        'image/png',
      );
    },
  );
}

class PermissionReminders extends RecordingReminders
    implements ReminderAvailability {
  bool allowed = false;
  int requests = 0;
  @override
  Future<void> requestPermissions() async {
    requests++;
  }

  @override
  Future<bool?> notificationsAllowed() async => allowed;
  @override
  Future<void> openNotificationSettings() async {}
  @override
  Future<void> schedule(StillOpenItem item, DateTime when) async {
    if (!allowed) throw const ReminderPermissionDenied();
    await super.schedule(item, when);
  }
}

class OperationGate {
  final started = Completer<void>();
  final release = Completer<void>();
  Future<void> wait() async {
    started.complete();
    await release.future;
  }
}

class GatedReminders extends RecordingReminders {
  OperationGate? cancelGate;
  OperationGate? cancelAllGate;
  OperationGate? scheduleGate;
  final scheduleAttempts = <DateTime>[];
  @override
  Future<void> cancel(int itemId) async {
    final gate = cancelGate;
    cancelGate = null;
    if (gate != null) await gate.wait();
    await super.cancel(itemId);
  }

  @override
  Future<void> cancelAll() async {
    final gate = cancelAllGate;
    cancelAllGate = null;
    if (gate != null) await gate.wait();
    await super.cancelAll();
  }

  @override
  Future<void> schedule(StillOpenItem item, DateTime when) async {
    scheduleAttempts.add(when);
    final gate = scheduleGate;
    scheduleGate = null;
    if (gate != null) await gate.wait();
    await super.schedule(item, when);
  }
}

class GatedFailStore extends MemoryContractStore {
  OperationGate? failGate;
  @override
  Future<void> setString(String key, String value) async {
    final gate = failGate;
    failGate = null;
    if (gate != null) {
      await gate.wait();
      throw const FileSystemException(
        'Controlled failed replacement reminder save',
      );
    }
    await super.setString(key, value);
  }
}

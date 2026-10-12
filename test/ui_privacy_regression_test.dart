// Regressions converted from the frozen user-impact audit.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:stillopen/main.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/diagnostics.dart';
import 'package:stillopen/src/models.dart';

// These probes now run as normal product regressions.
void main() {
  for (final kind in [
    TemplateType.quickNote,
    TemplateType.medicalClaim,
    TemplateType.longTerm,
  ]) {
    testWidgets(
      'UX-01 compact dark large text dense ${kind.name} detail remains usable',
      (tester) async {
        final controller = await _controller(
          item: StillOpenItem(
            id: 101,
            title:
                'Synthetic appointment paperwork to finish before the deadline',
            notes:
                'Synthetic notes with several details and a second follow-up.',
            state: ItemState.open,
            category: kind == TemplateType.medicalClaim
                ? Category.medical
                : Category.other,
            templateType: kind,
            recurrenceHint: kind == TemplateType.longTerm ? 'Every year' : '',
            dueText: 'Oct 12, 2030 09:30',
            waitingOn: 'Synthetic service department',
          ),
        );
        await controller.setThemePreference(AppThemePreference.dark);
        await _pump(tester, controller);
        await _expandFutureItems(tester);
        await tester.tap(find.text(controller.items.single.title));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('More').last);
        await tester.tap(find.text('More').last);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Control: expanded detail at default size',
        );

        await tester.binding.setSurfaceSize(const Size(360, 640));
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(() async {
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
          await tester.binding.setSurfaceSize(null);
        });
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Expanded detail must remain usable at 360x640, dark theme, 200% text',
        );
        await tester.ensureVisible(find.text('Due date').last);
        await tester.tap(find.text('Due date').last);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Dense-detail date action must open without overflow',
        );
      },
    );
  }

  testWidgets('UX-02 deleting an item offers confirmation or undo', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller);
    await tester.longPress(find.text(controller.items.single.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete task'));
    await tester.pumpAndSettle();
    final hasUndo = tester
        .widgetList<SnackBar>(find.byType(SnackBar))
        .any((bar) => bar.action?.label.toLowerCase() == 'undo');
    expect(
      controller.items.isNotEmpty || hasUndo,
      isTrue,
      reason:
          'One menu tap must not irreversibly delete an item without confirmation or undo',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.items, hasLength(1));
  });

  testWidgets('UX-02 deleting an attachment offers confirmation or undo', (
    tester,
  ) async {
    final controller = await _controller();
    await controller.addNoteAttachment(
      controller.items.single,
      'Synthetic attachment note',
    );
    await _pump(tester, controller);
    await tester.tap(find.text(controller.items.single.title));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Attachments'));
    await tester.tap(find.text('Attachments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete attachment'));
    await tester.pumpAndSettle();
    final hasUndo = tester
        .widgetList<SnackBar>(find.byType(SnackBar))
        .any((bar) => bar.action?.label.toLowerCase() == 'undo');
    expect(
      controller.attachments.isNotEmpty || hasUndo,
      isTrue,
      reason:
          'Attachment deletion must offer confirmation or recovery from an accidental tap',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.attachments, hasLength(1));
  });

  testWidgets('UX-02 clear local data cancellation retains the item control', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Clear local data'));
    await tester.tap(find.text('Clear local data'));
    await tester.pumpAndSettle();
    expect(find.text('Clear local data?'), findsOneWidget);
    expect(controller.items, hasLength(1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.items, hasLength(1));
  });

  testWidgets('UX-03 quick add storage failure shows a recoverable user error', (
    tester,
  ) async {
    final store = AuditStore();
    final controller = StillOpenController(store: store);
    await controller.load();
    await _pump(tester, controller);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick note'));
    await tester.pumpAndSettle();
    const title = 'Synthetic unsaved draft that must remain editable';
    await tester.enterText(find.byKey(const Key('quick_add_title')), title);
    store.failWrites = true;
    await tester.tap(find.byKey(const Key('quick_add_save')));
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason:
          'Storage failures should be handled by the UI instead of escaping the save callback',
    );
    expect(
      find.textContaining(
        RegExp('failed|could not|unable|try again', caseSensitive: false),
      ),
      findsWidgets,
      reason: 'A failed save must explain that the item is not safely saved',
    );
    expect(find.byKey(const Key('quick_add_title')), findsOneWidget);
    expect(store.values['stillopen_snapshot_v2'], isNull);
    store.failWrites = false;
    await tester.tap(find.byKey(const Key('quick_add_save')));
    await tester.pumpAndSettle();
    expect(controller.items.single.title, title);
    expect(store.values['stillopen_snapshot_v2'], contains(title));
  });

  test(
    'UX-04 generic runtime diagnostics exclude synthetic private title and notes',
    () async {
      final controller = await _controller(
        item: const StillOpenItem(
          id: 501,
          title: 'Synthetic Mira Halden confidential appointment',
          notes: 'Synthetic confidential treatment follow-up',
          state: ItemState.open,
          category: Category.medical,
        ),
      );
      final diagnostics = StillOpenDiagnostics.instance;
      diagnostics.clearForTests();
      addTearDown(diagnostics.clearForTests);
      diagnostics.recordFlutterError(
        FlutterErrorDetails(
          exception: StateError(
            'Unable to save ${controller.items.single.title}; '
            'note=${controller.items.single.notes}',
          ),
        ),
      );
      final exported = controller.exportDiagnosticsJson(
        runtimeDiagnostics: diagnostics.toJson(),
      );
      expect(
        exported,
        isNot(contains(controller.items.single.title)),
        reason:
            'Diagnostics promise to exclude item titles, including error-message copies',
      );
      expect(exported, isNot(contains(controller.items.single.notes)));
    },
  );

  test(
    'UX-04 incoming share stack diagnostics exclude synthetic private text',
    () async {
      final controller = await _controller();
      final diagnostics = StillOpenDiagnostics.instance;
      diagnostics.clearForTests();
      addTearDown(diagnostics.clearForTests);
      const privateText = 'Synthetic Mira Halden private errand';
      diagnostics.recordError(
        source: 'incoming_share_stream',
        message: 'Cannot import $privateText',
        stack: '#0 provider failure for $privateText',
      );
      final exported = controller.exportDiagnosticsJson(
        runtimeDiagnostics: diagnostics.toJson(),
      );
      expect(
        exported,
        isNot(contains(privateText)),
        reason:
            'Incoming share redaction must cover diagnostic fields beyond message',
      );
    },
  );

  test('UX-04 diagnostics redact URL path email and filename control', () async {
    final controller = await _controller();
    final exported = controller.exportDiagnosticsJson(
      runtimeDiagnostics: {
        'recent_errors': [
          {
            'message':
                'https://example.invalid/private synthetic@example.invalid '
                '/tmp/synthetic/private-record.pdf content://provider/synthetic',
          },
        ],
      },
    );
    for (final privateValue in [
      'example.invalid',
      'private-record.pdf',
      'content://provider',
      '/tmp/',
    ]) {
      expect(exported, isNot(contains(privateValue)));
    }
  });

  testWidgets(
    'UX-01 screenshot compact dense detail with Roboto retains failure evidence',
    (tester) async {
      // This capture uses Flutter's shipped Roboto instead of the test-only Ahem
      // glyphs. It remains a widget render, not native device proof.
      await tester.runAsync(() async {
        final config =
            jsonDecode(
                  await File('.dart_tool/package_config.json').readAsString(),
                )
                as Map<String, dynamic>;
        final packages = config['packages'] as List<dynamic>;
        final flutter = packages.cast<Map<String, dynamic>>().singleWhere(
          (package) => package['name'] == 'flutter',
        );
        final sdkRoot = Directory.fromUri(
          Uri.parse(flutter['rootUri'] as String),
        ).parent.parent;
        final bytes = await File(
          '${sdkRoot.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ).readAsBytes();
        for (final family in ['Roboto', 'Ahem']) {
          final loader = FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
        }
      });
      final controller = await _controller(
        item: const StillOpenItem(
          id: 101,
          title: 'Synthetic appointment paperwork',
          notes: 'Synthetic notes with a second follow-up.',
          state: ItemState.open,
          category: Category.medical,
          templateType: TemplateType.medicalClaim,
          dueText: 'Oct 12, 2030 09:30',
          waitingOn: 'Synthetic service department',
        ),
      );
      await controller.setThemePreference(AppThemePreference.dark);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: StillOpenApp(
            controller: controller,
            incomingShareSource: const EmptyAuditShareSource(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandFutureItems(tester);
      await tester.tap(find.text(controller.items.single.title));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('More').last);
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Roboto default-size control',
      );

      final errors = <String>[];
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) =>
          errors.add(details.exceptionAsString());
      addTearDown(() async {
        FlutterError.onError = previousErrorHandler;
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.binding.setSurfaceSize(null);
      });
      try {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2.0;
        await tester.pumpAndSettle();
        await _capture(
          tester,
          boundaryKey,
          'ux-01-compact-dark-200pct-detail-top.png',
        );
        await tester.ensureVisible(find.text('Due date').last);
        await tester.pumpAndSettle();
        await _capture(
          tester,
          boundaryKey,
          'ux-01-compact-dark-200pct-detail-fields.png',
        );
        await tester.runAsync(() async {
          final out = Directory(
            '../../../runtime/user-impact-audit/screenshots',
          );
          await out.create(recursive: true);
          await File('${out.path}/ux-01-widget-render.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'classification': 'WIDGET_RENDER_NOT_NATIVE_DEVICE',
              'font':
                  'Flutter SDK Roboto-Regular loaded as Roboto and Ahem fallback',
              'logical_size': [360, 640],
              'text_scale': 2.0,
              'theme': 'dark',
              'fixture': 'synthetic medical claim, expanded More details',
              'observed_render_errors': errors,
              'desired_invariant_passed': errors.isEmpty,
            }),
          );
        });
      } finally {
        FlutterError.onError = previousErrorHandler;
      }
      expect(
        errors,
        isEmpty,
        reason:
            'Screenshots were preserved before checking the no-overflow invariant; '
            'a captured defect must still fail this probe',
      );
    },
  );
}

Future<void> _expandFutureItems(WidgetTester tester) async {
  final toggle = find.byKey(const Key('far_future_toggle'));
  expect(toggle, findsOneWidget);
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final snapshot = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await snapshot.toByteData(format: ui.ImageByteFormat.png);
      final out = Directory('../../../runtime/user-impact-audit/screenshots');
      await out.create(recursive: true);
      await File(
        '${out.path}/$filename',
      ).writeAsBytes(png!.buffer.asUint8List());
    } finally {
      snapshot.dispose();
    }
  });
}

Future<StillOpenController> _controller({StillOpenItem? item}) async {
  final fixture =
      item ??
      const StillOpenItem(
        id: 101,
        title: 'Synthetic audit item',
        state: ItemState.open,
        category: Category.other,
      );
  final store = AuditStore();
  store.values['stillopen_items_v1'] = jsonEncode([fixture.toJson()]);
  final controller = StillOpenController(store: store);
  await controller.load();
  return controller;
}

Future<void> _pump(WidgetTester tester, StillOpenController controller) async {
  await tester.pumpWidget(
    StillOpenApp(
      controller: controller,
      incomingShareSource: const EmptyAuditShareSource(),
    ),
  );
  await tester.pumpAndSettle();
}

class AuditStore implements StillOpenStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    if (failWrites) throw StateError('Synthetic storage unavailable');
    values[key] = value;
  }
}

class EmptyAuditShareSource implements IncomingShareSource {
  const EmptyAuditShareSource();

  @override
  Future<List<SharedMediaFile>> getInitialMedia() async => const [];

  @override
  Future<List<IncomingShareExtra>> getInitialExtras() async => const [];

  @override
  Stream<List<SharedMediaFile>> getMediaStream() => const Stream.empty();

  @override
  Stream<List<IncomingShareExtra>> getExtraStream() => const Stream.empty();

  @override
  Future<void> reset() async {}
}

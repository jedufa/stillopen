import 'package:clock/clock.dart';

// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as notifications;
import 'package:open_filex/open_filex.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

import 'src/controller.dart';
import 'src/attachment_paths.dart';
import 'src/date_logic.dart';
import 'src/diagnostics.dart';
import 'src/incoming_share/incoming_share_ingestor.dart';
import 'src/incoming_share/ios_pending_share_store.dart';
import 'src/models.dart';
import 'src/notification_service.dart';
import 'src/recurrence.dart';
import 'src/rules.dart';

class _StillOpenPalette {
  const _StillOpenPalette({
    required this.backgroundTop,
    required this.background,
    required this.panel,
    required this.panelAlt,
    required this.text,
    required this.muted,
    required this.border,
    required this.accent,
    required this.accentSoft,
    required this.waiting,
    required this.waitingSoft,
    required this.warning,
    required this.warningSoft,
    required this.done,
    required this.doneSoft,
    required this.danger,
  });

  final Color backgroundTop;
  final Color background;
  final Color panel;
  final Color panelAlt;
  final Color text;
  final Color muted;
  final Color border;
  final Color accent;
  final Color accentSoft;
  final Color waiting;
  final Color waitingSoft;
  final Color warning;
  final Color warningSoft;
  final Color done;
  final Color doneSoft;
  final Color danger;
}

const _lightPalette = _StillOpenPalette(
  backgroundTop: Color(0xFFFBF6ED),
  background: Color(0xFFF7F3EE),
  panel: Color(0xFFFFFDF7),
  panelAlt: Color(0xFFF1E8DC),
  text: Color(0xFF24211D),
  muted: Color(0xFF5F574E),
  border: Color(0xFFCFC3B5),
  accent: Color(0xFF245F58),
  accentSoft: Color(0xFFDDECE7),
  waiting: Color(0xFF48607C),
  waitingSoft: Color(0xFFE9EEF6),
  warning: Color(0xFF8A5A12),
  warningSoft: Color(0xFFF9EED9),
  done: Color(0xFF386B4F),
  doneSoft: Color(0xFFE5F1EA),
  danger: Color(0xFF8B3A33),
);

const _darkPalette = _StillOpenPalette(
  backgroundTop: Color(0xFF191713),
  background: Color(0xFF12110F),
  panel: Color(0xFF211F1B),
  panelAlt: Color(0xFF302B24),
  text: Color(0xFFF5EFE5),
  muted: Color(0xFFC1B6A7),
  border: Color(0xFF4A4338),
  accent: Color(0xFF8FD6CA),
  accentSoft: Color(0xFF1D3C37),
  waiting: Color(0xFFAFC3E7),
  waitingSoft: Color(0xFF243147),
  warning: Color(0xFFEBC171),
  warningSoft: Color(0xFF45351C),
  done: Color(0xFFA8D8B9),
  doneSoft: Color(0xFF203B2B),
  danger: Color(0xFFE79A91),
);

_StillOpenPalette _palette = _lightPalette;
Color get _backgroundTop => _palette.backgroundTop;
Color get _background => _palette.background;
Color get _panel => _palette.panel;
Color get _panelAlt => _palette.panelAlt;
Color get _text => _palette.text;
Color get _muted => _palette.muted;
Color get _border => _palette.border;
Color get _accent => _palette.accent;
Color get _accentSoft => _palette.accentSoft;
Color get _waiting => _palette.waiting;
Color get _waitingSoft => _palette.waitingSoft;
Color get _warning => _palette.warning;
Color get _warningSoft => _palette.warningSoft;
Color get _done => _palette.done;
Color get _doneSoft => _palette.doneSoft;
Color get _danger => _palette.danger;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final diagnostics = StillOpenDiagnostics.instance;
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    diagnostics.recordFlutterError(details);
    previousFlutterError?.call(details);
  };
  ui.PlatformDispatcher.instance.onError = diagnostics.recordPlatformError;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const StillOpenApp());
}

class StillOpenApp extends StatefulWidget {
  const StillOpenApp({
    super.key,
    StillOpenController? controller,
    IncomingShareSource? incomingShareSource,
    IncomingShareIngestor? incomingShareIngestor,
    this.notificationPlugin,
  }) : _controller = controller,
       _incomingShareSource = incomingShareSource,
       _incomingShareIngestor = incomingShareIngestor;

  final StillOpenController? _controller;
  final IncomingShareSource? _incomingShareSource;
  final IncomingShareIngestor? _incomingShareIngestor;
  final notifications.FlutterLocalNotificationsPlugin? notificationPlugin;

  @override
  State<StillOpenApp> createState() => _StillOpenAppState();
}

abstract class IncomingShareSource {
  Stream<List<SharedMediaFile>> getMediaStream();
  Future<List<SharedMediaFile>> getInitialMedia();
  Stream<List<IncomingShareExtra>> getExtraStream();
  Future<List<IncomingShareExtra>> getInitialExtras();
  Future<void> reset();
}

class IncomingShareExtra {
  const IncomingShareExtra({required this.text, required this.isUrl});

  final String text;
  final bool isUrl;

  factory IncomingShareExtra.fromMap(Map<Object?, Object?> map) {
    return IncomingShareExtra(
      text: (map['text'] as String? ?? '').trim(),
      isUrl: map['isUrl'] as bool? ?? false,
    );
  }
}

class ReceiveSharingIncomingShareSource implements IncomingShareSource {
  const ReceiveSharingIncomingShareSource();

  static const _methodChannel = MethodChannel(
    'stillopen/incoming_share_extras',
  );
  static const _eventChannel = EventChannel(
    'stillopen/incoming_share_extras_stream',
  );

  @override
  Stream<List<SharedMediaFile>> getMediaStream() =>
      ReceiveSharingIntent.instance.getMediaStream();

  @override
  Future<List<SharedMediaFile>> getInitialMedia() =>
      ReceiveSharingIntent.instance.getInitialMedia();

  @override
  Stream<List<IncomingShareExtra>> getExtraStream() {
    return _eventChannel.receiveBroadcastStream().map((event) {
      final rawItems = (event as List<Object?>? ?? const <Object?>[]);
      return rawItems
          .whereType<Map<Object?, Object?>>()
          .map(IncomingShareExtra.fromMap)
          .where((extra) => extra.text.isNotEmpty)
          .toList();
    });
  }

  @override
  Future<List<IncomingShareExtra>> getInitialExtras() async {
    final rawItems = await _methodChannel.invokeListMethod<Object?>(
      'getInitialShareExtras',
    );
    return (rawItems ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(IncomingShareExtra.fromMap)
        .where((extra) => extra.text.isNotEmpty)
        .toList();
  }

  @override
  Future<void> reset() async {
    await ReceiveSharingIntent.instance.reset();
    await _methodChannel.invokeMethod<void>('resetInitialShareExtras');
  }
}

class _StillOpenAppState extends State<StillOpenApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final LocalReminderScheduler _reminders = LocalReminderScheduler(
    plugin: widget.notificationPlugin,
    onNotificationPayload: _handleNotificationPayload,
  );
  String? _pendingNotificationPayload;
  late final StillOpenController controller =
      widget._controller ??
      StillOpenController(
        attachmentDirectoryProvider: applicationAttachmentDirectory,
        reminderScheduler: _reminders,
      );
  late final IncomingShareSource _incomingShareSource =
      widget._incomingShareSource ?? const ReceiveSharingIncomingShareSource();
  IncomingShareIngestor? _incomingShareIngestor;
  late final Future<void> _startupFuture;
  StreamSubscription<List<SharedMediaFile>>? _incomingShareSubscription;
  StreamSubscription<List<IncomingShareExtra>>? _incomingShareExtraSubscription;
  final List<IncomingShareExtra> _pendingShareExtras = [];
  Timer? _timeRefreshTimer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timeRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_disposed) controller.refreshTimeStatuses();
    });
    _startupFuture = _start();
    unawaited(_startupFuture);
  }

  @override
  void dispose() {
    _disposed = true;
    _timeRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _incomingShareSubscription?.cancel();
    _incomingShareExtraSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.refreshTimeStatuses();
      unawaited(controller.reconcileNotifications());
      unawaited(_ingestIosPendingShares());
    }
  }

  Future<void> _start() async {
    try {
      await controller.load();
    } on Object catch (error, stackTrace) {
      _recordIncomingShareError('incoming_share_startup', error, stackTrace);
      rethrow;
    }
    if (_disposed || !mounted) return;
    if (widget._controller == null || widget.notificationPlugin != null) {
      try {
        _pendingNotificationPayload ??= await _reminders
            .initialNotificationPayload();
      } on Object catch (error, stackTrace) {
        StillOpenDiagnostics.instance.recordError(
          source: 'reminders',
          message: 'Notification launch lookup failed: ${error.runtimeType}',
          stack: stackTrace.toString(),
        );
      }
    }
    if (_pendingNotificationPayload != null) {
      _handleNotificationPayload(_pendingNotificationPayload);
    }
    _incomingShareIngestor = widget._incomingShareIngestor;
    if (_incomingShareIngestor == null) {
      try {
        final store = await MethodChannelPendingShareStore.create();
        if (store != null) {
          _incomingShareIngestor = IncomingShareIngestor(
            controller: controller,
            store: store,
          );
        }
      } on Object catch (error, stackTrace) {
        _recordIncomingShareError('ios_pending_share_store', error, stackTrace);
      }
    }
    await _ingestIosPendingShares();
    if (_disposed || !mounted) return;
    _listenForIncomingShares();
    try {
      _pendingShareExtras.addAll(await _incomingShareSource.getInitialExtras());
      final media = await _incomingShareSource.getInitialMedia();
      if (_disposed || !mounted) return;
      await _handleIncomingSharedMedia(media);
      if (media.isNotEmpty && !_disposed && mounted) {
        await _incomingShareSource.reset();
      }
    } on Object catch (error, stackTrace) {
      _recordIncomingShareError('incoming_share_initial', error, stackTrace);
    }
  }

  void _handleNotificationPayload(String? payload) {
    if (payload == null || payload.isEmpty || _disposed) return;
    if (!controller.loaded) {
      _pendingNotificationPayload = payload;
      return;
    }
    _pendingNotificationPayload = null;
    final id = int.tryParse(payload);
    if (id == null || !controller.items.any((item) => item.id == id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _navigatorKey.currentContext;
      if (_disposed || context == null) return;
      final item = controller.items.where((item) => item.id == id).firstOrNull;
      if (item == null) return;
      controller.selectTab(StillOpenRules.tabForState(item.state));
      unawaited(_showDetailSheet(context, controller, id));
    });
    // A native response can arrive while Flutter is idle. Registering a
    // post-frame callback alone does not request the frame that will open it.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _ingestIosPendingShares() async {
    if (_disposed || !mounted) return;
    final ingestor = _incomingShareIngestor;
    if (ingestor == null) return;
    try {
      await ingestor.ingestPendingShares();
    } on Object catch (error, stackTrace) {
      _recordIncomingShareError('ios_pending_share_ingest', error, stackTrace);
    }
  }

  void _listenForIncomingShares() {
    _incomingShareExtraSubscription = _incomingShareSource
        .getExtraStream()
        .listen(
          (extras) => _pendingShareExtras.addAll(extras),
          onError: (Object error, StackTrace stackTrace) {
            _recordIncomingShareError(
              'incoming_share_extra_stream',
              error,
              stackTrace,
            );
          },
        );
    _incomingShareSubscription = _incomingShareSource.getMediaStream().listen(
      (media) => unawaited(_handleIncomingSharedMediaSafely(media)),
      onError: (Object error, StackTrace stackTrace) {
        _recordIncomingShareError('incoming_share_stream', error, stackTrace);
      },
    );
  }

  Future<void> _handleIncomingSharedMediaSafely(
    List<SharedMediaFile> media,
  ) async {
    try {
      if (_hasFilesWithoutText(media) && _pendingShareExtras.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await _handleIncomingSharedMedia(media);
    } on Object catch (error, stackTrace) {
      _recordIncomingShareError('incoming_share_stream', error, stackTrace);
    }
  }

  Future<void> _handleIncomingSharedMedia(List<SharedMediaFile> media) async {
    if (_disposed || !mounted) return;
    if (media.isEmpty) return;
    final extra = _takePendingShareExtra();
    final textParts = media
        .where(
          (file) =>
              file.type == SharedMediaType.text ||
              file.type == SharedMediaType.url,
        )
        .map((file) => file.path.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    if (extra != null) textParts.insert(0, extra.text);
    final files = media
        .where(
          (file) =>
              file.type == SharedMediaType.image ||
              file.type == SharedMediaType.file,
        )
        .map(
          (file) => IncomingSharedFile(
            path: file.path,
            mimeType: file.mimeType,
            name: _fileNameFromPath(file.path),
            isImage:
                file.type == SharedMediaType.image ||
                (file.mimeType?.startsWith('image/') ?? false),
          ),
        )
        .toList();
    if (textParts.isNotEmpty || files.isNotEmpty) {
      await controller.addSharedContent(
        text: textParts.isEmpty ? null : textParts.join('\n'),
        isUrl:
            (extra?.isUrl ?? false) ||
            media.any((file) => file.type == SharedMediaType.url),
        files: files,
      );
    }
  }

  bool _hasFilesWithoutText(List<SharedMediaFile> media) {
    final hasText = media.any(
      (file) =>
          file.type == SharedMediaType.text || file.type == SharedMediaType.url,
    );
    final hasFiles = media.any(
      (file) =>
          file.type == SharedMediaType.image ||
          file.type == SharedMediaType.file,
    );
    return hasFiles && !hasText;
  }

  IncomingShareExtra? _takePendingShareExtra() {
    if (_pendingShareExtras.isEmpty) return null;
    return _pendingShareExtras.removeAt(0);
  }

  void _recordIncomingShareError(
    String source,
    Object error,
    StackTrace stackTrace,
  ) {
    StillOpenDiagnostics.instance.recordError(
      source: source,
      message: 'Incoming share handling failed: ${error.runtimeType}',
      stack: stackTrace.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        final dark = switch (controller.themePreference) {
          AppThemePreference.system => platformBrightness == Brightness.dark,
          AppThemePreference.light => false,
          AppThemePreference.dark => true,
        };
        _palette = dark ? _darkPalette : _lightPalette;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
        );
        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'StillOpen',
          theme: _themeFor(_lightPalette, Brightness.light),
          darkTheme: _themeFor(_darkPalette, Brightness.dark),
          themeMode: switch (controller.themePreference) {
            AppThemePreference.system => ThemeMode.system,
            AppThemePreference.light => ThemeMode.light,
            AppThemePreference.dark => ThemeMode.dark,
          },
          home: StillOpenHome(controller: controller),
        );
      },
    );
  }
}

ThemeData _themeFor(_StillOpenPalette palette, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: brightness,
    primary: palette.accent,
    secondary: palette.waiting,
    surface: palette.panel,
    error: palette.danger,
  );
  return ThemeData(
    colorScheme: scheme.copyWith(
      onPrimary: brightness == Brightness.dark
          ? const Color(0xFF08201D)
          : Colors.white,
      onSurface: palette.text,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.panel,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.panel,
      surfaceTintColor: Colors.transparent,
    ),
    scaffoldBackgroundColor: palette.background,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.text,
      contentTextStyle: TextStyle(color: palette.background),
    ),
    useMaterial3: true,
  );
}

class StillOpenHome extends StatefulWidget {
  const StillOpenHome({super.key, required this.controller});

  final StillOpenController controller;

  @override
  State<StillOpenHome> createState() => _StillOpenHomeState();
}

class _StillOpenHomeState extends State<StillOpenHome> {
  StillOpenController get controller => widget.controller;
  bool showFarFuture = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final message = controller.snackbarMessage;
          if (message == null) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
          controller.clearSnackbar();
        });
        final items = _groupedItems(controller, showFarFuture: showFarFuture);
        return Scaffold(
          backgroundColor: _background,
          floatingActionButton: Semantics(
            label: 'Add item',
            button: true,
            child: FloatingActionButton(
              tooltip: 'Add item',
              onPressed: () => _showCaptureMenuDialog(context, controller),
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              child: Icon(Icons.add),
            ),
          ),
          body: SafeArea(
            child: controller.loaded
                ? Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_backgroundTop, _background],
                      ),
                    ),
                    child: Column(
                      children: [
                        _TopBar(controller: controller),
                        _TabBar(controller: controller),
                        _DomainBar(controller: controller),
                        if (controller.showTemplateShortcuts)
                          _TemplateShortcuts(controller: controller),
                        if (controller.query.isNotEmpty)
                          _SearchActiveBar(controller: controller),
                        Expanded(
                          child: items.isEmpty
                              ? _EmptyState(controller: controller)
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    10,
                                    14,
                                    104,
                                  ),
                                  itemCount: items.length,
                                  itemBuilder: (context, index) {
                                    final entry = items[index];
                                    return entry.futureToggle
                                        ? Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton.icon(
                                              key: const Key(
                                                'far_future_toggle',
                                              ),
                                              onPressed: () => setState(
                                                () => showFarFuture =
                                                    !showFarFuture,
                                              ),
                                              icon: Icon(
                                                showFarFuture
                                                    ? Icons.expand_less
                                                    : Icons.expand_more,
                                              ),
                                              label: Text(entry.header!),
                                            ),
                                          )
                                        : entry.header != null
                                        ? _GroupHeader(label: entry.header!)
                                        : Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: _ItemCard(
                                              item: entry.item!,
                                              controller: controller,
                                              onTap: () => _showDetailSheet(
                                                context,
                                                controller,
                                                entry.item!.id,
                                              ),
                                              onLongPress: () =>
                                                  _showRowActionDialog(
                                                    context,
                                                    controller,
                                                    entry.item!,
                                                  ),
                                            ),
                                          );
                                  },
                                ),
                        ),
                      ],
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        );
      },
    );
  }
}

class _TemplateShortcuts extends StatelessWidget {
  const _TemplateShortcuts({required this.controller});
  final StillOpenController controller;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        for (final template in [
          TemplateType.medicalClaim,
          TemplateType.schoolHomework,
          TemplateType.longTerm,
        ])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              key: Key('template_shortcut_${template.name}'),
              avatar: Icon(_templateIcon(template), size: 18),
              label: Text('New ${_templateLabel(template)}'),
              onPressed: () async {
                await controller.createFromTemplate(template);
                final id = controller.selectedItemId;
                if (context.mounted && id != null) {
                  await _showDetailSheet(context, controller, id);
                }
              },
            ),
          ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final StillOpenController controller;

  @override
  Widget build(BuildContext context) {
    final open = controller.countForTab(HomeTab.open);
    final draft = controller.countForTab(HomeTab.draft);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: const SizedBox(
              width: 38,
              height: 38,
              child: Icon(Icons.check_circle_outline, size: 32),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'StillOpen',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _text,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$open open · $draft draft',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: _muted, height: 1),
                ),
              ],
            ),
          ),
          _FloatingIconButton(
            tooltip: 'Search',
            icon: Icons.search,
            onPressed: () => _showSearchDialog(context, controller),
          ),
          const SizedBox(width: 8),
          _FloatingIconButton(
            tooltip: 'Add from camera',
            icon: Icons.camera_alt,
            onPressed: () => _capturePhotoAsItem(context, controller),
          ),
          const SizedBox(width: 8),
          _FloatingIconButton(
            tooltip: 'Create item',
            icon: Icons.auto_awesome,
            accent: true,
            onPressed: () => _showSmartCaptureDialog(context, controller),
          ),
          const SizedBox(width: 8),
          _FloatingIconButton(
            tooltip: 'Settings',
            icon: Icons.settings,
            onPressed: () => _showSettingsDialog(context, controller),
          ),
        ],
      ),
    );
  }
}

class _FloatingIconButton extends StatelessWidget {
  const _FloatingIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.accent = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panel,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Semantics(
          label: tooltip,
          button: true,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, color: accent ? _accent : _muted, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.controller});

  final StillOpenController controller;

  @override
  Widget build(BuildContext context) {
    return _FloatingCard(
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 0),
      borderRadius: 20,
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: HomeTab.values.map((tab) {
            final selected = controller.selectedTab == tab;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => controller.selectTab(tab),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected ? _accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${_tabLabel(tab)} ${controller.countForTab(tab)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? _accent : _muted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                      height: 1,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _DomainBar extends StatelessWidget {
  const _DomainBar({required this.controller});

  final StillOpenController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _showFilterSortSheet(context, controller),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: controller.domainFilter == DomainFilter.all
                      ? _panelAlt
                      : _accentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  controller.domainFilter == DomainFilter.all
                      ? 'All domains'
                      : _domainLabel(controller.domainFilter),
                  style: TextStyle(
                    color: controller.domainFilter == DomainFilter.all
                        ? _muted
                        : _accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (controller.domainFilter != DomainFilter.all) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () =>
                    controller.selectDomainFilter(DomainFilter.all),
                child: Text('Clear'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchActiveBar extends StatelessWidget {
  const _SearchActiveBar({required this.controller});

  final StillOpenController controller;

  @override
  Widget build(BuildContext context) {
    return _FloatingCard(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      borderRadius: 16,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Search: ${controller.query}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () => controller.setQuery(''),
              child: Text('Clear'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingCard extends StatelessWidget {
  const _FloatingCard({
    required this.child,
    this.margin = EdgeInsets.zero,
    this.borderRadius = 16,
    this.elevation = 3,
  });

  final Widget child;
  final EdgeInsets margin;
  final double borderRadius;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      elevation: elevation,
      shadowColor: Colors.black26,
      color: _panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: _border.withValues(alpha: 0.25)),
      ),
      child: child,
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        label,
        style: TextStyle(
          color: _muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.controller,
    required this.onTap,
    required this.onLongPress,
  });

  final StillOpenItem item;
  final StillOpenController controller;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return _FloatingCard(
      borderRadius: 16,
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CategoryIcon(category: item.category),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (item.priority == Priority.high) ...[
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _danger,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rowMetaHint(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.dateLabel,
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    _StatusChip(
                      label: _itemStatusLabel(item, controller),
                      item: item,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _itemStatusLabel(StillOpenItem item, StillOpenController controller) {
  final label = statusLabel(item);
  if (label != 'Reminder set') return label;
  if (!controller.notificationsEnabled) return 'Notifications off';
  if (controller.notificationPermissionGranted == false) {
    return 'Notifications blocked';
  }
  return controller.notificationPermissionGranted == true
      ? label
      : 'Reminder saved';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.item});

  final String label;
  final StillOpenItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Waiting' => _waitingSoft,
      'Findable' || 'Sample source' || 'Reminder set' => _doneSoft,
      'Needs date' ||
      'Needs reminder' ||
      'Needs decision' ||
      'Needs follow-up' ||
      'Missing info' ||
      'Overdue' ||
      'Follow-up overdue' ||
      'Reminder due' ||
      'Due for follow-up' ||
      'Notifications blocked' ||
      'Notifications off' ||
      'Waiting too long' ||
      'Source needs check' => _warningSoft,
      _ => _panelAlt,
    };
    final textColor = switch (label) {
      'Waiting' => _waiting,
      'Findable' || 'Sample source' || 'Reminder set' => _done,
      'Needs date' ||
      'Needs reminder' ||
      'Needs decision' ||
      'Needs follow-up' ||
      'Missing info' ||
      'Overdue' ||
      'Follow-up overdue' ||
      'Reminder due' ||
      'Due for follow-up' ||
      'Notifications blocked' ||
      'Notifications off' ||
      'Waiting too long' ||
      'Source needs check' => _warning,
      _ => _muted,
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    final icon = switch (category) {
      Category.medical => Icons.local_hospital_outlined,
      Category.school => Icons.school_outlined,
      Category.shopping => Icons.shopping_bag_outlined,
      Category.money => Icons.account_balance_outlined,
      Category.documents => Icons.description_outlined,
      Category.home => Icons.home_outlined,
      Category.family => Icons.groups_outlined,
      Category.work => Icons.work_outline,
      Category.longTerm => Icons.event_repeat_outlined,
      _ => Icons.radio_button_unchecked,
    };
    final tint = _categoryColor(category);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: tint),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final StillOpenController controller;

  @override
  Widget build(BuildContext context) {
    final searching = controller.query.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 48, 14, 120),
      children: [
        _FloatingCard(
          borderRadius: 22,
          elevation: 5,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  searching ? 'No matching items' : 'Nothing is still open.',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  searching
                      ? 'Search looks across title, source, person, note, and recognized text.'
                      : 'Capture a form, screenshot, note, or receipt and StillOpen will keep it visible.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _muted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                  ),
                  onPressed: searching
                      ? () => controller.setQuery('')
                      : () => _showQuickAddDialog(context, controller),
                  child: Text(searching ? 'Clear search' : 'Add item'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupedEntry {
  const _GroupedEntry.header(this.header) : item = null, futureToggle = false;
  const _GroupedEntry.item(this.item) : header = null, futureToggle = false;
  const _GroupedEntry.future(this.header) : item = null, futureToggle = true;

  final String? header;
  final StillOpenItem? item;
  final bool futureToggle;
}

List<_GroupedEntry> _groupedItems(
  StillOpenController controller, {
  bool showFarFuture = false,
}) {
  final items = controller.visibleItems;
  if (controller.selectedTab != HomeTab.open || controller.query.isNotEmpty) {
    return items.map(_GroupedEntry.item).toList();
  }
  final needsAttention = items.where(itemNeedsAttention).toList();
  final waiting = items
      .where(
        (item) =>
            item.state == ItemState.waiting && !needsAttention.contains(item),
      )
      .toList();
  final later = items
      .where(
        (item) =>
            item.state == ItemState.open && !needsAttention.contains(item),
      )
      .toList();
  final days = controller.farFutureThreshold.days;
  final cutoff = days == null ? null : calendarDayAfter(clock.now(), days);
  final farFuture = cutoff == null
      ? <StillOpenItem>[]
      : later.where((item) {
          final date = nextItemActionDate(item);
          return date != null && date.isAfter(cutoff);
        }).toList();
  final nearLater = later.where((item) => !farFuture.contains(item)).toList();
  return [
    if (needsAttention.isNotEmpty) ...[
      const _GroupedEntry.header('Needs attention'),
      ...needsAttention.map(_GroupedEntry.item),
    ],
    if (waiting.isNotEmpty) ...[
      const _GroupedEntry.header('Waiting'),
      ...waiting.map(_GroupedEntry.item),
    ],
    if (nearLater.isNotEmpty) ...[
      const _GroupedEntry.header('Later'),
      ...nearLater.map(_GroupedEntry.item),
    ],
    if (farFuture.isNotEmpty) ...[
      _GroupedEntry.future(
        'Later than ${controller.farFutureThreshold.label} (${farFuture.length})',
      ),
      if (showFarFuture) ...farFuture.map(_GroupedEntry.item),
    ],
  ];
}

Color _categoryColor(Category category) => switch (category) {
  Category.family => const Color(0xFF8A655C),
  Category.school => const Color(0xFF4B6A95),
  Category.medical => const Color(0xFFD32F2F),
  Category.longTerm => const Color(0xFF55705B),
  Category.home => const Color(0xFF6E7350),
  Category.shopping => const Color(0xFF6D5C8A),
  Category.money => const Color(0xFF9A7425),
  Category.work => const Color(0xFF5B6474),
  Category.documents => const Color(0xFF6A665C),
  Category.personal => const Color(0xFF52765F),
  Category.other => const Color(0xFF7A746B),
};

Color _domainColor(DomainFilter filter) => switch (filter) {
  DomainFilter.medical => _categoryColor(Category.medical),
  DomainFilter.school => _categoryColor(Category.school),
  DomainFilter.family => _categoryColor(Category.family),
  DomainFilter.longTerm => _categoryColor(Category.longTerm),
  DomainFilter.home => _categoryColor(Category.home),
  DomainFilter.shopping => _categoryColor(Category.shopping),
  DomainFilter.money => _categoryColor(Category.money),
  DomainFilter.documents => _categoryColor(Category.documents),
  DomainFilter.all => _muted,
};

Color _templateColor(TemplateType template) => switch (template) {
  TemplateType.medicalClaim => _categoryColor(Category.medical),
  TemplateType.schoolHomework ||
  TemplateType.school => _categoryColor(Category.school),
  TemplateType.longTerm => _categoryColor(Category.longTerm),
  TemplateType.home => _categoryColor(Category.home),
  TemplateType.shoppingReturn => _categoryColor(Category.shopping),
  TemplateType.money => _categoryColor(Category.money),
  TemplateType.document => _categoryColor(Category.documents),
  TemplateType.quickNote => _categoryColor(Category.personal),
  TemplateType.other => _categoryColor(Category.other),
};

String _tabLabel(HomeTab tab) => switch (tab) {
  HomeTab.draft => 'Draft',
  HomeTab.open => 'Open',
  HomeTab.done => 'Done',
};

Future<void> _showSearchDialog(
  BuildContext context,
  StillOpenController controller,
) async {
  final textController = TextEditingController(text: controller.query);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Search'),
      content: TextField(
        key: const Key('search_field'),
        controller: textController,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search title, source, person, note',
        ),
        onChanged: controller.setQuery,
      ),
      actions: [
        TextButton(
          onPressed: () {
            controller.setQuery('');
            Navigator.pop(context);
          },
          child: Text('Clear'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Done'),
        ),
      ],
    ),
  );
}

Future<void> _showFilterSortSheet(
  BuildContext context,
  StillOpenController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Filter items'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final filter in DomainFilter.values)
              _DialogActionRow(
                label: controller.domainFilter == filter
                    ? '${_domainLabel(filter)} · current'
                    : _domainLabel(filter),
                selected: controller.domainFilter == filter,
                icon: _domainIcon(filter),
                tint: _domainColor(filter),
                onTap: () {
                  controller.selectDomainFilter(filter);
                  Navigator.pop(context);
                },
              ),
            Padding(
              padding: EdgeInsets.only(top: 8, left: 4, bottom: 8),
              child: Text(
                'Sort',
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final mode in SortMode.values)
              _DialogActionRow(
                label: controller.sortMode == mode
                    ? '${_sortLabel(mode)} · current'
                    : _sortLabel(mode),
                selected: controller.sortMode == mode,
                icon: Icons.sort,
                tint: _muted,
                onTap: () {
                  controller.selectSort(mode);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _showQuickAddDialog(
  BuildContext context,
  StillOpenController controller,
) async {
  final parentContext = context;
  final titleController = TextEditingController();
  var tomorrow = true;
  var highPriority = false;
  var category = Category.personal;
  var categoryEdited = false;
  String? saveError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Add to StillOpen'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('quick_add_title'),
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'What is still open?',
                ),
              ),
              if (saveError != null) ...[
                const SizedBox(height: 8),
                Text(
                  saveError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'Quick settings',
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    selected: tomorrow,
                    label: Text(tomorrow ? 'Tomorrow · selected' : 'Tomorrow'),
                    onSelected: (_) => setState(() => tomorrow = !tomorrow),
                  ),
                  FilterChip(
                    selected: highPriority,
                    label: Text(
                      highPriority ? 'High · selected' : 'High priority',
                    ),
                    onSelected: (_) =>
                        setState(() => highPriority = !highPriority),
                  ),
                  FilterChip(
                    selected: category == Category.personal,
                    label: Text(
                      category == Category.personal
                          ? 'Personal · selected'
                          : 'Personal',
                    ),
                    onSelected: (_) => setState(() {
                      categoryEdited = true;
                      category = category == Category.personal
                          ? Category.other
                          : Category.personal;
                    }),
                  ),
                  ActionChip(
                    label: Text('More'),
                    onPressed: () async {
                      final picked = await _showCategoryPickDialog(
                        context,
                        category,
                      );
                      if (picked == null) return;
                      setState(() {
                        categoryEdited = true;
                        category = picked;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          FilledButton(
            key: const Key('quick_add_save'),
            onPressed: () async {
              bool saved;
              try {
                saved = await controller.quickAdd(
                  title: titleController.text,
                  tomorrow: tomorrow,
                  highPriority: highPriority,
                  category: category,
                  categoryEdited: categoryEdited,
                );
              } on Object {
                if (context.mounted) {
                  setState(
                    () =>
                        saveError = 'Could not save locally. Please try again.',
                  );
                }
                return;
              }
              final itemId = controller.selectedItemId;
              if (saved && context.mounted) {
                Navigator.pop(context);
                await Future<void>.delayed(Duration.zero);
                if (parentContext.mounted && itemId != null) {
                  await _showDetailSheet(parentContext, controller, itemId);
                }
              }
            },
            child: Text('Save Open'),
          ),
        ],
      ),
    ),
  );
}

Future<Category?> _showCategoryPickDialog(
  BuildContext context,
  Category current,
) {
  return showDialog<Category>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Choose category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final category in Category.values)
              _DialogActionRow(
                label: category == current
                    ? '${category.displayName} · current'
                    : category.displayName,
                selected: category == current,
                icon: _categoryIconData(category),
                tint: _categoryColor(category),
                onTap: () => Navigator.pop(context, category),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
      ],
    ),
  );
}

Future<void> _capturePhotoAsItem(
  BuildContext context,
  StillOpenController controller,
) async {
  final image = await ImagePicker().pickImage(source: ImageSource.camera);
  if (image == null) return;
  await controller.quickAdd(
    title: 'Photo follow-up',
    category: Category.documents,
    categoryEdited: true,
  );
  final item = controller.selectedItem;
  if (item == null) return;
  await controller.addAttachment(
    item: item,
    uri: image.path,
    label: _fileNameFromPath(image.path).ifBlank('Photo'),
    sourceType: SourceType.camera,
  );
  if (context.mounted) {
    await _showDetailSheet(context, controller, item.id);
  }
}

Future<void> _captureFileAsItem(
  BuildContext context,
  StillOpenController controller,
) async {
  final file = await openFile();
  if (file == null) return;
  await controller.quickAdd(
    title: _fileNameFromPath(file.path).ifBlank('Document follow-up'),
    category: Category.documents,
    categoryEdited: true,
  );
  final item = controller.selectedItem;
  if (item == null) return;
  await controller.addAttachment(
    item: item,
    uri: file.path,
    label: _fileNameFromPath(file.path).ifBlank('File'),
    sourceType: _pickedFileSourceType(file),
    mimeType: file.mimeType,
  );
  if (context.mounted) {
    await _showDetailSheet(context, controller, item.id);
  }
}

Future<void> _showSmartCaptureDialog(
  BuildContext context,
  StillOpenController controller,
) async {
  final parentContext = context;
  final textController = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Smart capture'),
      content: TextField(
        controller: textController,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          hintText: 'Describe what is still open',
          helperText: 'Creates an item and infers the category.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final saved = await controller.quickAdd(title: textController.text);
            final itemId = controller.selectedItemId;
            if (!context.mounted) return;
            Navigator.pop(context);
            await Future<void>.delayed(Duration.zero);
            if (saved && parentContext.mounted && itemId != null) {
              await _showDetailSheet(parentContext, controller, itemId);
            }
          },
          child: Text('Create'),
        ),
      ],
    ),
  );
}

Future<void> _showCaptureMenuDialog(
  BuildContext context,
  StillOpenController controller,
) async {
  final parentContext = context;
  var showAllTemplates = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final templates = showAllTemplates
            ? [
                TemplateType.medicalClaim,
                TemplateType.schoolHomework,
                TemplateType.school,
                TemplateType.longTerm,
                TemplateType.home,
                TemplateType.shoppingReturn,
                TemplateType.money,
                TemplateType.document,
                TemplateType.other,
              ]
            : [
                TemplateType.medicalClaim,
                TemplateType.schoolHomework,
                TemplateType.longTerm,
              ];
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text('Add to StillOpen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialogActionRow(
                  label: 'Quick note',
                  icon: Icons.edit_note,
                  tint: _categoryColor(Category.personal),
                  onTap: () {
                    Navigator.pop(context);
                    _showQuickAddDialog(parentContext, controller);
                  },
                ),
                _DialogActionRow(
                  label: 'Take photo',
                  icon: Icons.camera_alt,
                  tint: _categoryColor(Category.personal),
                  onTap: () async {
                    Navigator.pop(context);
                    await _capturePhotoAsItem(parentContext, controller);
                  },
                ),
                _DialogActionRow(
                  label: 'Pick file',
                  icon: Icons.file_open,
                  tint: _categoryColor(Category.documents),
                  onTap: () async {
                    Navigator.pop(context);
                    await _captureFileAsItem(parentContext, controller);
                  },
                ),
                Padding(
                  padding: EdgeInsets.only(top: 8, left: 4, bottom: 8),
                  child: Text(
                    'Templates',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final template in templates)
                  _DialogActionRow(
                    label: _templateLabel(template),
                    subtitle: _templateDescription(template),
                    icon: _templateIcon(template),
                    tint: _templateColor(template),
                    onTap: () async {
                      await controller.createFromTemplate(template);
                      final itemId = controller.selectedItemId;
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      await Future<void>.delayed(Duration.zero);
                      if (parentContext.mounted && itemId != null) {
                        await _showDetailSheet(
                          parentContext,
                          controller,
                          itemId,
                        );
                      }
                    },
                  ),
                if (!showAllTemplates)
                  _DialogActionRow(
                    label: 'More templates',
                    icon: Icons.more_horiz,
                    tint: _muted,
                    onTap: () => setState(() => showAllTemplates = true),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> _showSettingsDialog(
  BuildContext context,
  StillOpenController controller,
) async {
  String settingsTitle = '';
  String settingsBody = '';
  var showReminderDefaults = false;
  var showExportImport = false;
  var confirmClearData = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        if (showReminderDefaults) {
          return _ReminderDefaultsDialog(
            preset: controller.defaultReminderPreset,
            hour: controller.defaultReminderHour,
            minute: controller.defaultReminderMinute,
            onSave: (preset, hour, minute) async {
              await controller.setDefaultReminder(preset, hour, minute);
              if (context.mounted) setState(() => showReminderDefaults = false);
            },
            onClose: () => setState(() => showReminderDefaults = false),
          );
        }
        if (showExportImport) {
          return _ExportImportDialog(
            controller: controller,
            onClose: () => setState(() => showExportImport = false),
          );
        }
        if (settingsTitle.isNotEmpty) {
          return _SettingsInfoDialog(
            title: settingsTitle,
            body: settingsBody,
            onClose: () => setState(() {
              settingsTitle = '';
              settingsBody = '';
            }),
          );
        }
        if (confirmClearData) {
          return AlertDialog(
            title: Text('Clear local data?'),
            content: Text(
              'This removes all StillOpen items stored on this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => setState(() => confirmClearData = false),
                child: Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  await controller.clearAllData();
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text('Clear data'),
              ),
            ],
          );
        }
        final recentSources = controller.items
            .map((item) => item.sourceLabel)
            .where((label) => label.trim().isNotEmpty)
            .toSet()
            .take(2)
            .join(' · ');
        return AlertDialog(
          title: Text('Settings'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _SettingsSection(
                    title: 'Basics',
                    children: [
                      _SettingsListRow(
                        title: 'How StillOpen works',
                        subtitle:
                            'Draft, Open, Done, what matters, local limits',
                        icon: Icons.article_outlined,
                        onTap: () => setState(() {
                          settingsTitle = 'How StillOpen works';
                          settingsBody =
                              'Capture loose ends into Draft, move the ones that need attention to Open, and close them only when they are handled, filed, or intentionally ignored.';
                        }),
                      ),
                      _SettingsListRow(
                        title: 'Reminders',
                        subtitle:
                            'New draft default · ${controller.defaultReminderPreset} ${controller.defaultReminderHour.toString().padLeft(2, '0')}:${controller.defaultReminderMinute.toString().padLeft(2, '0')}',
                        icon: Icons.calendar_month_outlined,
                        onTap: () =>
                            setState(() => showReminderDefaults = true),
                      ),
                      _SettingsListRow(
                        title: 'Sources',
                        subtitle: recentSources.isEmpty
                            ? 'Recent sources · none yet'
                            : recentSources,
                        icon: Icons.file_open_outlined,
                        onTap: () => setState(() {
                          settingsTitle = 'Sources';
                          settingsBody =
                              '${controller.attachments.length} attachments are stored locally. Image, camera, and note attachments can be added from item details.';
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'App behavior',
                    children: [
                      _SettingsListRow(
                        title: 'Show template shortcuts',
                        subtitle: controller.showTemplateShortcuts
                            ? 'Medical, School, Long-term and other starts are shown on home'
                            : 'Home stays lifecycle-first by default',
                        icon: Icons.article_outlined,
                        onTap: () async {
                          await controller.setTemplateShortcutsVisible(
                            !controller.showTemplateShortcuts,
                          );
                          if (context.mounted) setState(() {});
                        },
                      ),
                      _SettingsListRow(
                        title: 'Collapse items more than',
                        subtitle: controller.farFutureThreshold.label,
                        icon: Icons.calendar_month_outlined,
                        onTap: () async {
                          await controller.cycleFarFutureThreshold();
                          if (context.mounted) setState(() {});
                        },
                      ),
                      _SettingsListRow(
                        title: 'Draft follow-up',
                        subtitle: 'Keep captured items visible',
                        icon: Icons.edit_note,
                        onTap: () => setState(() {
                          settingsTitle = 'Draft follow-up';
                          settingsBody =
                              'Captured items stay in Draft until you move them to Open, ignore them, or delete them from the detail screen.';
                        }),
                      ),
                      _SettingsListRow(
                        title: 'Notifications',
                        subtitle: notificationAvailabilityLabel(controller),
                        icon: Icons.notifications_none,
                        onTap: () async {
                          await controller.refreshNotificationPermission();
                          if (!context.mounted) return;
                          await _showNotificationSettingsDialog(
                            context,
                            controller,
                          );
                          if (context.mounted) setState(() {});
                        },
                      ),
                      _SettingsListRow(
                        title: 'Appearance',
                        subtitle: controller.themePreference.displayLabel,
                        icon: Icons.image_outlined,
                        onTap: () async {
                          await controller.setThemePreference(
                            controller.themePreference.next,
                          );
                          if (context.mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Data',
                    children: [
                      _SettingsListRow(
                        title: 'Local data',
                        subtitle:
                            '${controller.items.length} items · ${controller.attachments.length} attachments',
                        icon: Icons.home_outlined,
                        onTap: () => setState(() {
                          settingsTitle = 'Local data';
                          settingsBody =
                              'StillOpen stores app data locally on this device.';
                        }),
                      ),
                      _SettingsListRow(
                        title: 'Export / import',
                        subtitle: 'Back up data or move phones',
                        icon: Icons.file_open_outlined,
                        onTap: () => setState(() => showExportImport = true),
                      ),
                      _SettingsListRow(
                        title: 'Diagnostics',
                        subtitle: 'Export a redacted local support file',
                        icon: Icons.bug_report_outlined,
                        onTap: () => _shareDiagnosticsFile(controller),
                      ),
                      _SettingsListRow(
                        title: 'Privacy',
                        subtitle: 'Local-first data and permissions',
                        icon: Icons.lock_outline,
                        onTap: () => setState(() {
                          settingsTitle = 'Privacy';
                          settingsBody =
                              'StillOpen stores items and attachments in app-local storage. It does not send app data to a server. Backup exports include your items and readable attachments, so save them somewhere you trust. Diagnostics exports are redacted and exclude item titles, notes, attachment paths, and attachment bytes.';
                        }),
                      ),
                      _SettingsListRow(
                        title: 'Clear local data',
                        subtitle: 'Remove all items on this device',
                        icon: Icons.delete_outline,
                        tint: _danger,
                        onTap: () => setState(() => confirmClearData = true),
                      ),
                      _SettingsListRow(
                        title: 'About',
                        subtitle: 'Local-first open-loop tracking',
                        icon: Icons.person_outline,
                        onTap: () => setState(() {
                          settingsTitle = 'About';
                          settingsBody =
                              'StillOpen keeps open loops visible until they are handled, filed, or intentionally ignored.';
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your data stays on this device unless you export or share it.',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Done'),
            ),
          ],
        );
      },
    ),
  );
}

String notificationAvailabilityLabel(StillOpenController controller) {
  if (!controller.notificationsEnabled) return 'Off on this device';
  return switch (controller.notificationPermissionGranted) {
    true => 'Enabled on this device',
    false => 'Blocked in device settings',
    null => 'Device permission not verified',
  };
}

Future<void> _showNotificationSettingsDialog(
  BuildContext context,
  StillOpenController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Notifications'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const Key('notifications_enabled_switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable reminders'),
              subtitle: Text(notificationAvailabilityLabel(controller)),
              value: controller.notificationsEnabled,
              onChanged: controller.setNotificationsEnabled,
            ),
            if (controller.notificationPermissionGranted == false)
              const Text(
                'Reminders stay saved, but this device is blocking notifications. Allow them in device settings.',
              ),
            TextButton.icon(
              onPressed: () async {
                try {
                  await controller.openNotificationSettings();
                } on Object {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not open device settings. Open this app in your device settings.',
                        ),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open device settings'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  ),
);

Future<void> _shareDiagnosticsFile(StillOpenController controller) async {
  const fileName = 'stillopen-diagnostics.json';
  final diagnostics = controller.exportDiagnosticsJson(
    runtimeDiagnostics: StillOpenDiagnostics.instance.toJson(),
  );
  final diagnosticsFile = XFile.fromData(
    Uint8List.fromList(utf8.encode(diagnostics)),
    mimeType: 'application/json',
    name: fileName,
  );
  await SharePlus.instance.share(
    ShareParams(
      files: [diagnosticsFile],
      fileNameOverrides: [fileName],
      subject: 'StillOpen diagnostics',
    ),
  );
}

Future<bool> _confirmDelete(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _showRowActionDialog(
  BuildContext context,
  StillOpenController controller,
  StillOpenItem item,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.state == ItemState.draft) ...[
              _DialogActionRow(
                label: 'Make Open',
                icon: Icons.arrow_forward,
                onTap: () async {
                  await controller.makeOpen(item);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              _DialogActionRow(
                label: 'Share item',
                icon: Icons.share,
                onTap: () async {
                  Navigator.pop(context);
                  await _copyItemSummary(context, item);
                },
              ),
              _DialogActionRow(
                label: 'Keep draft',
                icon: Icons.close,
                onTap: () => Navigator.pop(context),
              ),
              _DialogActionRow(
                label: 'Delete task',
                icon: Icons.delete_outline,
                onTap: () async {
                  if (!await _confirmDelete(context, 'Delete task?')) return;
                  await controller.deleteItem(item);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              _DialogActionRow(
                label: 'Ignore',
                icon: Icons.visibility_off_outlined,
                onTap: () async {
                  await controller.ignoreDraft(item);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ] else if (item.state == ItemState.done ||
                item.state == ItemState.ignored) ...[
              _DialogActionRow(
                label: 'Reopen',
                icon: Icons.undo,
                onTap: () async {
                  await controller.reopen(item);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              _DialogActionRow(
                label: 'Share item',
                icon: Icons.share,
                onTap: () async {
                  Navigator.pop(context);
                  await _copyItemSummary(context, item);
                },
              ),
              _DialogActionRow(
                label: 'View history',
                icon: Icons.history,
                onTap: () {
                  Navigator.pop(context);
                  _showDetailSheet(context, controller, item.id);
                },
              ),
              _DialogActionRow(
                label: 'Delete task',
                icon: Icons.delete_outline,
                onTap: () async {
                  if (!await _confirmDelete(context, 'Delete task?')) return;
                  await controller.deleteItem(item);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              _DialogActionRow(
                label: 'More',
                icon: Icons.more_horiz,
                onTap: () {
                  Navigator.pop(context);
                  _showDetailSheet(context, controller, item.id);
                },
              ),
            ] else ...[
              _DialogActionRow(
                label:
                    item.templateType == TemplateType.longTerm &&
                        RecurrenceRule.parse(item.recurrenceHint) != null
                    ? 'Complete cycle'
                    : 'Mark Done',
                icon: Icons.check,
                onTap: () async {
                  await controller.markDone(item);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              if (item.templateType == TemplateType.longTerm &&
                  RecurrenceRule.parse(item.recurrenceHint) != null)
                _DialogActionRow(
                  label: 'Stop repeating',
                  icon: Icons.stop_circle_outlined,
                  onTap: () async {
                    await controller.stopLongTermRecurrence(item);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              _DialogActionRow(
                label: 'Share item',
                icon: Icons.share,
                onTap: () async {
                  Navigator.pop(context);
                  await _copyItemSummary(context, item);
                },
              ),
              _DialogActionRow(
                label: 'Change status',
                icon: Icons.swap_horiz,
                onTap: () {
                  Navigator.pop(context);
                  _showDetailSheet(context, controller, item.id);
                },
              ),
              _DialogActionRow(
                label: 'Edit reminder',
                icon: Icons.notifications_none,
                onTap: () {
                  Navigator.pop(context);
                  _showDetailSheet(context, controller, item.id);
                },
              ),
              _DialogActionRow(
                label: 'Delete task',
                icon: Icons.delete_outline,
                onTap: () async {
                  if (!await _confirmDelete(context, 'Delete task?')) return;
                  await controller.deleteItem(item);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              _DialogActionRow(
                label: 'More',
                icon: Icons.more_horiz,
                onTap: () {
                  Navigator.pop(context);
                  _showDetailSheet(context, controller, item.id);
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _copyItemSummary(BuildContext context, StillOpenItem item) async {
  final lines = [
    item.title,
    minimalCategoryLabel(item),
    minimalStatusSentence(item),
    if (item.dueText.isNotEmpty) 'Due: ${item.dueText}',
    if (item.reminderText.isNotEmpty) 'Reminder: ${item.reminderText}',
    if (item.waitingOn.isNotEmpty) 'Waiting on: ${item.waitingOn}',
    if (item.notes.isNotEmpty) 'Notes: ${item.notes}',
  ];
  await Clipboard.setData(ClipboardData(text: lines.join('\n')));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Item copied to clipboard')));
}

Future<void> _showDetailSheet(
  BuildContext context,
  StillOpenController controller,
  int itemId,
) async {
  controller.openDetails(itemId);
  await showDialog<void>(
    context: context,
    builder: (context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final details = controller.selectedDetails;
        if (details == null) return const SizedBox.shrink();
        return _AndroidStyleDetailDialog(
          details: details,
          controller: controller,
        );
      },
    ),
  );
  controller.closeDetails();
}

class _AndroidStyleDetailDialog extends StatefulWidget {
  const _AndroidStyleDetailDialog({
    required this.details,
    required this.controller,
  });

  final ItemWithDetails details;
  final StillOpenController controller;

  @override
  State<_AndroidStyleDetailDialog> createState() =>
      _AndroidStyleDetailDialogState();
}

class _AndroidStyleDetailDialogState extends State<_AndroidStyleDetailDialog> {
  late final TextEditingController titleController = TextEditingController(
    text: widget.details.item.title,
  );
  bool editingTitle = false;
  bool showMore = false;

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  Future<void> _commitTitle() async {
    if (!editingTitle) return;
    await widget.controller.renameItem(
      widget.details.item,
      titleController.text,
    );
    if (mounted) setState(() => editingTitle = false);
  }

  void _startTitleEdit() {
    setState(() => editingTitle = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: titleController.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    final item = details.item;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: _panel,
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 4),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: editingTitle
                ? TextField(
                    controller: titleController,
                    autofocus: true,
                    selectionControls: materialTextSelectionControls,
                    maxLines: 2,
                    style: TextStyle(
                      color: _text,
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                    onSubmitted: (_) => _commitTitle(),
                    decoration: const InputDecoration(isDense: true),
                  )
                : InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _startTitleEdit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _text,
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
          ),
          TextButton(
            onPressed: () async {
              await _commitTitle();
              if (context.mounted) Navigator.pop(context);
            },
            child: Text('OK'),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MinimalItemStatusBlock(item: item),
              const SizedBox(height: 10),
              _MinimalFollowUpBlock(
                item: item,
                onSetReminder: () =>
                    _showReminderEditDialog(context, widget.controller, item),
                onPickDate: () =>
                    _showDateEditDialog(context, widget.controller, item),
              ),
              if (item.templateType == TemplateType.longTerm) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  key: const Key('edit_recurrence'),
                  onPressed: () => _showRecurrenceEditDialog(
                    context,
                    widget.controller,
                    item,
                  ),
                  icon: const Icon(Icons.event_repeat, size: 18),
                  label: Text(
                    item.recurrenceHint.isEmpty
                        ? 'Set repeat'
                        : 'Repeat: ${item.recurrenceHint}',
                  ),
                ),
                if (item.completedCycles > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      '${item.completedCycles} cycle${item.completedCycles == 1 ? '' : 's'} completed'
                      '${DateTime.tryParse(item.lastCycleCompletedAt) == null ? '' : ' · Last ${MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(item.lastCycleCompletedAt))}'}',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              _MinimalNextBlock(
                item: item,
                controller: widget.controller,
                onAddReminder: () =>
                    _showReminderEditDialog(context, widget.controller, item),
                onLongTermHandled: () => _showLongTermNextReminderDialog(
                  context,
                  widget.controller,
                  item,
                ),
                onAddUpdate: () => setState(() => showMore = true),
              ),
              const SizedBox(height: 12),
              _MinimalSourceBlock(
                details: details,
                controller: widget.controller,
              ),
              const SizedBox(height: 12),
              _CollapsibleSection(
                label: 'More',
                summary: 'Timeline · notes · steps · details',
                expanded: showMore,
                onToggle: () => setState(() => showMore = !showMore),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _DetailQuickFields(
                      item: item,
                      controller: widget.controller,
                      onEditText: (title, initial, save) =>
                          _showTextEditDialog(context, title, initial, save),
                      onEditDate: () =>
                          _showDateEditDialog(context, widget.controller, item),
                      onEditReminder: () => _showReminderEditDialog(
                        context,
                        widget.controller,
                        item,
                      ),
                      onEditWaiting: () => _showWaitingOnDialog(
                        context,
                        widget.controller,
                        item,
                      ),
                      onEditRecurrence: () => _showRecurrenceEditDialog(
                        context,
                        widget.controller,
                        item,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _LifecycleStrip(state: item.state),
                    const SizedBox(height: 10),
                    _StepsToFinishCard(details: details),
                    if (item.notes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _DetailSection(title: 'Notes', body: item.notes),
                    ],
                    const SizedBox(height: 10),
                    _StillOpenKnows(details: details),
                    const SizedBox(height: 10),
                    Text(
                      'Timeline',
                      style: TextStyle(
                        color: _text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _TimelineList(timeline: details.timeline),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _copyItemSummary(context, item),
                      icon: Icon(Icons.share, size: 17),
                      label: Text('Share item'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    if (item.state == ItemState.draft)
                      _AsyncTextButton(
                        onPressed: () => widget.controller.ignoreDraft(item),
                        child: Text('Ignore'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: const [],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 3),
          Text(body),
        ],
      ),
    );
  }
}

class _MinimalItemStatusBlock extends StatelessWidget {
  const _MinimalItemStatusBlock({required this.item});

  final StillOpenItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          minimalCategoryLabel(item),
          style: TextStyle(
            color: _muted,
            fontSize: 13,
            height: 1.15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          minimalStatusSentence(item),
          style: TextStyle(
            color: _text,
            fontSize: 17,
            height: 1.24,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MinimalFollowUpBlock extends StatelessWidget {
  const _MinimalFollowUpBlock({
    required this.item,
    required this.onSetReminder,
    required this.onPickDate,
  });

  final StillOpenItem item;
  final VoidCallback onSetReminder;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final line = minimalFollowUpLine(item);
    final needsFollowUp = line.startsWith('No follow-up set');
    final useStackedLayout = MediaQuery.textScalerOf(context).scale(1) > 1.2;
    final showReminderButton =
        needsFollowUp &&
        item.state != ItemState.done &&
        item.state != ItemState.ignored;
    final message = Text(
      line,
      style: TextStyle(
        color: needsFollowUp ? _muted : _text,
        fontSize: 14,
        height: 1.28,
        fontWeight: FontWeight.w500,
      ),
    );
    final reminderButton = TextButton(
      onPressed: onSetReminder,
      child: Text(
        'Set reminder',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPickDate,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: useStackedLayout
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  message,
                  if (showReminderButton)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: reminderButton,
                      ),
                    ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: message),
                  if (showReminderButton)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: reminderButton,
                    ),
                ],
              ),
      ),
    );
  }
}

class _MinimalNextBlock extends StatelessWidget {
  const _MinimalNextBlock({
    required this.item,
    required this.controller,
    required this.onAddReminder,
    required this.onLongTermHandled,
    required this.onAddUpdate,
  });

  final StillOpenItem item;
  final StillOpenController controller;
  final VoidCallback onAddReminder;
  final VoidCallback onLongTermHandled;
  final VoidCallback onAddUpdate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Next',
          style: TextStyle(
            color: _muted,
            fontSize: 12,
            height: 1.15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          minimalNextActionLabel(item),
          style: TextStyle(
            color: _text,
            fontSize: 15,
            height: 1.26,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _PrimaryActions(
          controller: controller,
          item: item,
          onAddReminder: onAddReminder,
          onLongTermHandled: onLongTermHandled,
          onAddUpdate: onAddUpdate,
          onCloseDetails: () => Navigator.pop(context),
        ),
        if (item.reminderText.isNotEmpty &&
            !{ItemState.done, ItemState.ignored}.contains(item.state) &&
            (!controller.notificationsEnabled ||
                controller.notificationPermissionGranted != true)) ...[
          const SizedBox(height: 8),
          Text(
            notificationAvailabilityLabel(controller),
            style: TextStyle(color: _warning),
          ),
          TextButton(
            onPressed: () =>
                _showNotificationSettingsDialog(context, controller),
            child: const Text('Notification settings'),
          ),
        ],
      ],
    );
  }
}

class _MinimalSourceBlock extends StatelessWidget {
  const _MinimalSourceBlock({required this.details, required this.controller});

  final ItemWithDetails details;
  final StillOpenController controller;

  @override
  Widget build(BuildContext context) {
    final savedCount = details.attachments
        .where((attachment) => attachment.uri.isNotEmpty)
        .length;
    return Material(
      color: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showAttachmentsDialog(context, controller, details.item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.upload_file, color: _accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attachments',
                      style: TextStyle(
                        color: _text,
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      savedCount == 0
                          ? minimalSourceStatus(details)
                          : '$savedCount ${savedCount == 1 ? "attachment" : "attachments"} saved',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                flex: 0,
                child: Text(
                  'Open',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    required this.label,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String label;
  final String summary;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: _text,
                          fontSize: 14,
                          height: 1.14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.16,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  flex: 0,
                  child: Text(
                    expanded ? 'Hide' : 'Show',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _accent,
                      fontSize: 12,
                      height: 1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) child,
      ],
    );
  }
}

class _DetailQuickFields extends StatelessWidget {
  const _DetailQuickFields({
    required this.item,
    required this.controller,
    required this.onEditText,
    required this.onEditDate,
    required this.onEditReminder,
    required this.onEditWaiting,
    required this.onEditRecurrence,
  });

  final StillOpenItem item;
  final StillOpenController controller;
  final void Function(
    String title,
    String initial,
    Future<void> Function(String value) save,
  )
  onEditText;
  final VoidCallback onEditDate;
  final VoidCallback onEditReminder;
  final VoidCallback onEditWaiting;
  final VoidCallback onEditRecurrence;

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      _QuickField(
        label: 'Due date',
        value: dueDateDisplay(item),
        onTap: onEditDate,
      ),
      _QuickField(
        label: 'Category',
        value: item.category.displayName,
        onTap: () async {
          final picked = await _showCategoryPickDialog(context, item.category);
          if (picked != null) await controller.setCategory(item, picked);
        },
      ),
      _QuickField(
        label: 'Waiting on',
        value: item.waitingOn.ifBlank('None'),
        onTap: onEditWaiting,
      ),
      _QuickField(
        label: 'Reminder',
        value: displayStillOpenDate(
          item.reminderText,
          item.reminderAt,
        ).ifBlank('None'),
        onTap: onEditReminder,
      ),
      if (item.templateType == TemplateType.longTerm)
        _QuickField(
          label: 'Recurrence',
          value: item.recurrenceHint.ifBlank('None'),
          onTap: onEditRecurrence,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        final columns = largeText || constraints.maxWidth < 300 ? 1 : 3;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final field in fields) SizedBox(width: width, child: field),
          ],
        );
      },
    );
  }
}

class _QuickField extends StatelessWidget {
  const _QuickField({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  softWrap: true,
                  style: TextStyle(
                    color: _muted,
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _text, fontSize: 12, height: 1.16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LifecycleStrip extends StatelessWidget {
  const _LifecycleStrip({required this.state});

  final ItemState state;

  @override
  Widget build(BuildContext context) {
    final active = switch (state) {
      ItemState.draft => 0,
      ItemState.done || ItemState.ignored => 2,
      _ => 1,
    };
    return Material(
      color: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            for (final entry in ['Draft', 'Open', 'Done'].indexed) ...[
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 1,
                            color: entry.$1 == 0 ? Colors.transparent : _border,
                          ),
                        ),
                        Container(
                          width: entry.$1 == active ? 12 : 8,
                          height: entry.$1 == active ? 12 : 8,
                          decoration: BoxDecoration(
                            color: entry.$1 == active ? _accent : _border,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: entry.$1 == 2 ? Colors.transparent : _border,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.$2,
                      style: TextStyle(
                        color: entry.$1 == active ? _accent : _muted,
                        fontSize: 11,
                        height: 1,
                        fontWeight: entry.$1 == active
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepsToFinishCard extends StatelessWidget {
  const _StepsToFinishCard({required this.details});

  final ItemWithDetails details;

  @override
  Widget build(BuildContext context) {
    final steps = details.steps.take(4).toList();
    return Material(
      color: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usual path',
              style: TextStyle(
                color: _text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 18, color: _accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _text, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StillOpenKnows extends StatelessWidget {
  const _StillOpenKnows({required this.details});

  final ItemWithDetails details;

  @override
  Widget build(BuildContext context) {
    final facts = stillOpenFacts(details).take(5).toList();
    if (facts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'StillOpen knows',
          style: TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: facts.map((fact) {
            final problem =
                fact.contains('Needs') ||
                fact.contains('No ') ||
                fact.contains('missing');
            return Chip(
              label: Text('${problem ? "!" : "✓"} $fact'),
              backgroundColor: problem ? _warningSoft : _accentSoft,
              labelStyle: TextStyle(
                color: problem ? _warning : _accent,
                fontSize: 12,
              ),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.timeline});

  final List<TimelineEvent> timeline;

  @override
  Widget build(BuildContext context) {
    final events = timeline;
    if (events.isEmpty) {
      return Text(
        'No timeline yet',
        style: TextStyle(color: _muted, fontSize: 13),
      );
    }
    return Column(
      children: [
        for (final event in events)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 7),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.label,
                        style: TextStyle(
                          color: _text,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        event.createdAt > 0
                            ? _timelineTimestamp(context, event.createdAt)
                            : event.eventTimeText.ifBlank('Time not recorded'),
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _timelineTimestamp(BuildContext context, int epoch) {
  final when = DateTime.fromMillisecondsSinceEpoch(epoch);
  final locale = MaterialLocalizations.of(context);
  return '${locale.formatMediumDate(when)} ${when.year} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(when))}';
}

String dueDateDisplay(StillOpenItem item) => displayStillOpenDate(
  item.dueText,
  item.dueAt,
).ifBlank(item.appointmentDateText.ifBlank('No due date'));

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({
    required this.controller,
    required this.item,
    required this.onAddReminder,
    required this.onLongTermHandled,
    required this.onAddUpdate,
    required this.onCloseDetails,
  });

  final StillOpenController controller;
  final StillOpenItem item;
  final VoidCallback onAddReminder;
  final VoidCallback onLongTermHandled;
  final VoidCallback onAddUpdate;
  final VoidCallback onCloseDetails;

  @override
  Widget build(BuildContext context) {
    if (item.state == ItemState.done || item.state == ItemState.ignored) {
      if (item.templateType == TemplateType.longTerm) {
        return _DetailActionRow(
          children: [
            _DetailActionButton(
              label: 'Set reminder',
              onPressed: onLongTermHandled,
            ),
            _DetailActionButton(
              label: 'Reopen',
              icon: Icons.undo,
              secondary: true,
              onPressed: () => controller.reopen(item),
            ),
          ],
        );
      }
      return _DetailActionRow(
        children: [
          _DetailActionButton(
            label: 'Reopen',
            icon: Icons.undo,
            onPressed: () => controller.reopen(item),
          ),
          _DetailActionButton(
            label: 'Keep done',
            secondary: true,
            onPressed: onCloseDetails,
          ),
        ],
      );
    }
    if (isMedicalWorkflowItem(item) && item.state != ItemState.draft) {
      return _DetailActionRow(
        children: [
          _DetailActionButton(
            label: _medicalActionLabel(item),
            onPressed: () => _runMedicalAction(item),
          ),
          _DetailActionButton(
            label: 'Mark Done',
            icon: Icons.check,
            onPressed: () async {
              await controller.markDone(item);
              onCloseDetails();
            },
          ),
        ],
      );
    }
    if (item.templateType == TemplateType.longTerm) {
      final recurring = RecurrenceRule.parse(item.recurrenceHint) != null;
      final booked =
          item.state == ItemState.waiting || item.waitingOn.isNotEmpty;
      if (booked) {
        return _DetailActionRow(
          children: [
            _DetailActionButton(
              label: 'Change reminder',
              secondary: true,
              onPressed: onAddReminder,
            ),
            _DetailActionButton(
              label: recurring ? 'Complete cycle' : 'Mark Done',
              icon: Icons.check,
              onPressed: recurring
                  ? () async {
                      await controller.markDone(item);
                      onCloseDetails();
                    }
                  : onLongTermHandled,
            ),
          ],
        );
      }
      return _DetailActionRow(
        children: [
          _DetailActionButton(
            label: 'Mark booked',
            onPressed: () => controller.markLongTermBooked(item),
          ),
          _DetailActionButton(
            label: recurring ? 'Complete cycle' : 'Mark Done',
            icon: Icons.check,
            onPressed: () async {
              await controller.markDone(item);
              onCloseDetails();
            },
          ),
        ],
      );
    }
    if (item.state == ItemState.draft) {
      return _DetailActionRow(
        children: [
          _DetailActionButton(
            label: 'Make Open',
            onPressed: () => controller.makeOpen(item),
          ),
          _DetailActionButton(
            label: 'Keep Draft',
            secondary: true,
            onPressed: onCloseDetails,
          ),
        ],
      );
    }
    if (item.state == ItemState.waiting) {
      return _DetailActionRow(
        children: [
          _DetailActionButton(label: 'Add update', onPressed: onAddUpdate),
          _DetailActionButton(
            label: 'Mark Done',
            icon: Icons.check,
            onPressed: () async {
              await controller.markDone(item);
              onCloseDetails();
            },
          ),
        ],
      );
    }
    return _DetailActionRow(
      children: [
        _DetailActionButton(
          label: item.reminderText.isEmpty ? 'Set reminder' : 'Edit reminder',
          onPressed: onAddReminder,
        ),
        _DetailActionButton(
          label: 'Mark Done',
          icon: Icons.check,
          onPressed: () async {
            await controller.markDone(item);
            onCloseDetails();
          },
        ),
      ],
    );
  }

  String _medicalActionLabel(StillOpenItem item) {
    final stage = item.claimStage.toLowerCase();
    if (stage.contains('waiting for appointment')) {
      return 'Have the appointment';
    }
    if (stage.contains('appointment done')) return 'Mark submitted';
    if (stage.contains('private response')) return 'Reimbursed';
    if (stage.contains('response received')) return 'Forward private';
    if (stage.contains('forwarded')) return 'Private response';
    if (stage.contains('reimbursed')) return 'Mark Done';
    if (stage.contains('submitted') ||
        stage.contains('waiting') ||
        item.state == ItemState.waiting) {
      return 'Response received';
    }
    return 'Book appointment';
  }

  Future<void> _runMedicalAction(StillOpenItem item) async {
    final stage = item.claimStage.toLowerCase();
    if (stage.contains('waiting for appointment')) {
      await controller.markMedicalAppointmentDone(item);
    } else if (stage.contains('appointment done')) {
      await controller.markMedicalSubmitted(item);
    } else if (stage.contains('private response')) {
      await controller.markMedicalReimbursed(item);
    } else if (stage.contains('response received')) {
      await controller.markMedicalForwarded(item);
    } else if (stage.contains('forwarded')) {
      await controller.markMedicalPrivateResponseReceived(item);
    } else if (stage.contains('reimbursed')) {
      await controller.markDone(item);
    } else if (stage.contains('submitted') ||
        stage.contains('waiting') ||
        item.state == ItemState.waiting) {
      await controller.markMedicalResponseReceived(item);
    } else {
      await controller.markMedicalAppointmentBooked(item);
    }
  }
}

class _DetailActionRow extends StatelessWidget {
  const _DetailActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final child in children) ...[
          if (child != children.first) const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ],
    );
  }
}

class _DetailActionButton extends StatefulWidget {
  const _DetailActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
  });

  final String label;
  final IconData? icon;
  final FutureOr<void> Function() onPressed;
  final bool secondary;

  @override
  State<_DetailActionButton> createState() => _DetailActionButtonState();
}

class _DetailActionButtonState extends State<_DetailActionButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
    final labelWidget = Text(
      widget.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    final onPressed = _busy ? null : _run;
    if (widget.secondary) {
      final outlinedStyle = OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      );
      if (widget.icon == null) {
        return OutlinedButton(
          onPressed: onPressed,
          style: outlinedStyle,
          child: labelWidget,
        );
      }
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(widget.icon, size: 18),
        label: labelWidget,
        style: outlinedStyle,
      );
    }
    if (widget.icon == null) {
      return FilledButton(
        onPressed: onPressed,
        style: buttonStyle,
        child: labelWidget,
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(widget.icon, size: 18),
      label: labelWidget,
      style: buttonStyle,
    );
  }
}

class _AsyncTextButton extends StatefulWidget {
  const _AsyncTextButton({required this.onPressed, required this.child});

  final FutureOr<void> Function() onPressed;
  final Widget child;

  @override
  State<_AsyncTextButton> createState() => _AsyncTextButtonState();
}

class _AsyncTextButtonState extends State<_AsyncTextButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(onPressed: _busy ? null : _run, child: widget.child);
  }
}

Future<void> _showDateEditDialog(
  BuildContext context,
  StillOpenController controller,
  StillOpenItem item,
) async {
  Future<void> pickDateAndTime(BuildContext dialogContext) async {
    final date = await showDatePicker(
      context: dialogContext,
      initialDate: clock.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !dialogContext.mounted) return;
    final time = await showTimePicker(
      context: dialogContext,
      initialTime: TimeOfDay(
        hour: controller.defaultReminderHour,
        minute: controller.defaultReminderMinute,
      ),
    );
    if (time == null) return;
    await controller.setPickedDueDateTime(
      item,
      date,
      hour: time.hour,
      minute: time.minute,
    );
    if (dialogContext.mounted) Navigator.pop(dialogContext);
  }

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(dateFieldLabel(item)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogActionRow(
            label: 'Today',
            icon: Icons.today,
            onTap: () async {
              await controller.setDateToday(item);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          _DialogActionRow(
            label: 'Tomorrow',
            icon: Icons.event,
            onTap: () async {
              await controller.setDateTomorrow(item);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          _DialogActionRow(
            label: 'This weekend',
            icon: Icons.weekend,
            onTap: () async {
              await controller.setDateThisWeekend(item);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          _DialogActionRow(
            label: 'Pick date',
            subtitle: 'Date picker, then time picker',
            icon: Icons.calendar_month,
            onTap: () => pickDateAndTime(context),
          ),
          _DialogActionRow(
            label:
                item.templateType == TemplateType.longTerm &&
                    item.recurrenceHint.isNotEmpty
                ? 'Clear date and repeat'
                : 'Clear date',
            icon: Icons.clear,
            tint: _danger,
            onTap: () async {
              await controller.clearDate(item);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _showReminderEditDialog(
  BuildContext context,
  StillOpenController controller,
  StillOpenItem item,
) async {
  Future<void> pickDateAndTime(BuildContext dialogContext) async {
    final date = await showDatePicker(
      context: dialogContext,
      initialDate: clock.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !dialogContext.mounted) return;
    final time = await showTimePicker(
      context: dialogContext,
      initialTime: TimeOfDay(
        hour: controller.defaultReminderHour,
        minute: controller.defaultReminderMinute,
      ),
    );
    if (time == null) return;
    await controller.setPickedReminder(
      item,
      date,
      hour: time.hour,
      minute: time.minute,
    );
    if (dialogContext.mounted) Navigator.pop(dialogContext);
  }

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item.reminderText.isEmpty ? 'Add reminder' : 'Edit reminder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogActionRow(
            label: 'Today 20:00',
            icon: Icons.notifications_active,
            onTap: () async {
              await controller.setReminderToday(item);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          _DialogActionRow(
            label: 'Tomorrow 20:00',
            icon: Icons.notifications,
            onTap: () async {
              await controller.setReminderTomorrow(item);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          _DialogActionRow(
            label: 'This weekend 20:00',
            icon: Icons.weekend,
            onTap: () async {
              await controller.setReminderThisWeekend(item);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          _DialogActionRow(
            label: 'Pick date and time',
            icon: Icons.calendar_month,
            onTap: () => pickDateAndTime(context),
          ),
          if (item.reminderText.isNotEmpty)
            _DialogActionRow(
              label:
                  item.templateType == TemplateType.longTerm &&
                      item.recurrenceHint.isNotEmpty
                  ? 'Remove reminder and repeat'
                  : 'Remove reminder',
              icon: Icons.clear,
              tint: _danger,
              onTap: () async {
                await controller.clearReminder(item);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _showLongTermNextReminderDialog(
  BuildContext context,
  StillOpenController controller,
  StillOpenItem item,
) async {
  final defaultNext = defaultNextReminderForRecurrence(item.recurrenceHint);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Set next reminder?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Keep the next cycle visible without turning the home screen into a calendar.',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 10),
            if (defaultNext != 'Pick date')
              _DialogActionRow(
                label: '${item.recurrenceHint}: $defaultNext',
                icon: Icons.event_repeat,
                onTap: () async {
                  await controller.setLongTermNextReminderFromRecurrence(item);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            for (final label in [
              'Tomorrow',
              '1 week',
              '1 month',
              '3 months',
              '6 months',
              '1 year',
            ])
              _DialogActionRow(
                label: label,
                icon: Icons.notifications,
                onTap: () async {
                  await controller.setLongTermNextReminder(item, label);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            _DialogActionRow(
              label: 'Pick date',
              subtitle: 'Use the date and time picker',
              icon: Icons.calendar_month,
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: calendarDayAfter(clock.now(), 1),
                  firstDate: calendarDayAfter(clock.now(), 1),
                  lastDate: DateTime(2100),
                );
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: controller.defaultReminderHour,
                    minute: controller.defaultReminderMinute,
                  ),
                );
                if (time == null || !context.mounted) return;
                await controller.completeLongTermCycle(
                  item,
                  nextReminder: DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  ),
                );
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await controller.stopLongTermRecurrence(item);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(
            item.recurrenceHint.isEmpty
                ? 'Finish without reminder'
                : 'Stop repeating',
          ),
        ),
      ],
    ),
  );
}

Future<void> _showRecurrenceEditDialog(
  BuildContext context,
  StillOpenController controller,
  StillOpenItem item,
) => showDialog<void>(
  context: context,
  builder: (_) => _RecurrenceEditDialog(controller: controller, item: item),
);

class _RecurrenceEditDialog extends StatefulWidget {
  const _RecurrenceEditDialog({required this.controller, required this.item});

  final StillOpenController controller;
  final StillOpenItem item;

  @override
  State<_RecurrenceEditDialog> createState() => _RecurrenceEditDialogState();
}

class _RecurrenceEditDialogState extends State<_RecurrenceEditDialog> {
  final customController = TextEditingController();
  String customError = '';

  @override
  void dispose() {
    customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AlertDialog(
      title: Text('Change recurrence'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose a cadence to schedule the next reminder. Completing a cycle schedules the following one.',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Current: ${item.recurrenceHint.ifBlank('None')}',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            for (final label in [
              'Daily',
              'Weekly',
              'Monthly',
              'Quarterly',
              'Every 6 months',
              'Yearly',
            ])
              _DialogActionRow(
                label: label == item.recurrenceHint
                    ? '$label · current'
                    : label,
                selected: label == item.recurrenceHint,
                icon: Icons.event_repeat,
                onTap: () async {
                  await widget.controller.setRecurrenceHint(item, label);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            _DialogActionRow(
              label: 'No recurrence',
              subtitle: 'Keep the next reminder as a one-time reminder',
              icon: Icons.clear,
              tint: _danger,
              onTap: () async {
                await widget.controller.setRecurrenceHint(item, '');
                if (context.mounted) Navigator.pop(context);
              },
            ),
            TextField(
              key: const Key('recurrence_custom_input'),
              controller: customController,
              decoration: InputDecoration(
                hintText: 'Every 2 years',
                helperText: 'Every N days, weeks, months, or years',
                errorText: customError.isEmpty ? null : customError,
              ),
              textInputAction: TextInputAction.done,
            ),
            if (item.recurrenceHint.isNotEmpty && item.state != ItemState.done)
              _DialogActionRow(
                label: 'Stop repeating and finish',
                icon: Icons.stop_circle_outlined,
                tint: _danger,
                onTap: () async {
                  await widget.controller.stopLongTermRecurrence(item);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
        FilledButton(
          key: const Key('recurrence_save_custom'),
          onPressed: () async {
            try {
              if (customController.text.trim().isEmpty) {
                setState(() => customError = 'Enter an interval');
                return;
              }
              await widget.controller.setRecurrenceHint(
                item,
                customController.text,
              );
              if (context.mounted) Navigator.pop(context);
            } on FormatException {
              setState(
                () => customError = 'Use Every N days, weeks, months, or years',
              );
            }
          },
          child: Text('Save recurrence'),
        ),
      ],
    );
  }
}

Future<void> _showWaitingOnDialog(
  BuildContext context,
  StillOpenController controller,
  StillOpenItem item,
) {
  const choices = [
    'Insurance',
    'School',
    'Caregiver',
    'Parent',
    'Merchant',
    'Doctor',
    'Child',
    'Provider',
  ];
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Waiting on'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in choices)
            _DialogActionRow(
              label: choice == item.waitingOn ? '$choice · current' : choice,
              icon: Icons.hourglass_bottom,
              selected: choice == item.waitingOn,
              tint: _waiting,
              onTap: () async {
                await controller.setWaitingOn(item, choice);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          _DialogActionRow(
            label: 'Clear waiting-on',
            icon: Icons.clear,
            tint: _danger,
            onTap: () async {
              await controller.setWaitingOn(item, '');
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _showAttachmentsDialog(
  BuildContext context,
  StillOpenController controller,
  StillOpenItem item,
) async {
  final picker = ImagePicker();
  final noteController = TextEditingController();

  Future<void> attachImage(ImageSource source) async {
    final image = await picker.pickImage(source: source);
    if (image == null) return;
    await controller.addAttachment(
      item: item,
      uri: image.path,
      label: _fileNameFromPath(image.path),
      sourceType: source == ImageSource.camera
          ? SourceType.camera
          : SourceType.image,
    );
  }

  Future<void> attachFile() async {
    final file = await openFile();
    if (file == null) return;
    await controller.addAttachment(
      item: item,
      uri: file.path,
      label: _fileNameFromPath(file.path).ifBlank('File'),
      sourceType: _pickedFileSourceType(file),
      mimeType: file.mimeType,
    );
  }

  Future<void> addNote(BuildContext dialogContext) async {
    final saved = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text('Note attachment'),
        content: TextField(
          controller: noteController,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(hintText: 'Write the note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await controller.addNoteAttachment(item, noteController.text);
    }
  }

  Future<void> renameAttachment(
    BuildContext dialogContext,
    ItemAttachment attachment,
  ) async {
    final label = await showDialog<String>(
      context: dialogContext,
      builder: (context) =>
          _AttachmentRenameDialog(initialLabel: attachment.label),
    );
    if (label != null) {
      await controller.renameAttachment(attachment, label);
    }
  }

  try {
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final details = controller.selectedDetails;
          final attachments = details?.attachments ?? const <ItemAttachment>[];
          return AlertDialog(
            title: Text('Attachments'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachments.isEmpty
                          ? 'No attachments yet.'
                          : '${attachments.length} ${attachments.length == 1 ? "attachment" : "attachments"} saved',
                      style: TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 10),
                    _AttachmentAddGrid(
                      onImage: () {
                        attachImage(ImageSource.gallery);
                      },
                      onCamera: () {
                        attachImage(ImageSource.camera);
                      },
                      onFile: () {
                        attachFile();
                      },
                      onNote: () {
                        addNote(context);
                      },
                    ),
                    if (attachments.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      for (final attachment in attachments)
                        _AttachmentRow(
                          attachment: attachment,
                          onOpen: () =>
                              _openAttachment(context, controller, attachment),
                          onRename: () => renameAttachment(context, attachment),
                          onDelete: () async {
                            if (await _confirmDelete(
                              context,
                              'Delete attachment?',
                            )) {
                              await controller.deleteAttachment(attachment);
                            }
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    noteController.dispose();
  }
}

class _AttachmentRenameDialog extends StatefulWidget {
  const _AttachmentRenameDialog({required this.initialLabel});

  final String initialLabel;

  @override
  State<_AttachmentRenameDialog> createState() =>
      _AttachmentRenameDialogState();
}

class _AttachmentRenameDialogState extends State<_AttachmentRenameDialog> {
  late final TextEditingController labelController = TextEditingController(
    text: widget.initialLabel,
  );

  @override
  void initState() {
    super.initState();
    labelController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: labelController.text.length,
    );
  }

  @override
  void dispose() {
    labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rename attachment'),
      content: TextField(
        key: const Key('attachment_rename_input'),
        controller: labelController,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Attachment label'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, labelController.text),
          child: Text('Save'),
        ),
      ],
    );
  }
}

class _AttachmentAddGrid extends StatelessWidget {
  const _AttachmentAddGrid({
    required this.onImage,
    required this.onCamera,
    required this.onFile,
    required this.onNote,
  });

  final VoidCallback onImage;
  final VoidCallback onCamera;
  final VoidCallback onFile;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _AttachmentAddButton(
                label: 'Image',
                icon: Icons.image,
                onPressed: onImage,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AttachmentAddButton(
                label: 'Camera',
                icon: Icons.photo_camera,
                onPressed: onCamera,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _AttachmentAddButton(
                label: 'File',
                icon: Icons.upload_file,
                onPressed: onFile,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AttachmentAddButton(
                label: 'Note',
                icon: Icons.article,
                onPressed: onNote,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentAddButton extends StatelessWidget {
  const _AttachmentAddButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final ItemAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final actions = [
      for (final action in [
        ('Open attachment', Icons.open_in_new, _muted, onOpen),
        ('Rename attachment', Icons.edit_outlined, _muted, onRename),
        ('Delete attachment', Icons.delete_outline, _danger, onDelete),
      ])
        Semantics(
          label: action.$1,
          button: true,
          child: IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: action.$4,
            icon: Icon(action.$2, color: action.$3),
            tooltip: action.$1,
          ),
        ),
    ];
    return Material(
      color: _panelAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 21;
            final description = Row(
              children: [
                Icon(_attachmentIcon(attachment.sourceType), color: _accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.label.ifBlank(
                          _sourceTypeLabel(attachment.sourceType),
                        ),
                        maxLines: stacked ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _attachmentSubtitle(attachment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  description,
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, runSpacing: 4, children: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: description),
                ...actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> _openAttachment(
  BuildContext context,
  StillOpenController controller,
  ItemAttachment attachment,
) async {
  if (attachment.uri.startsWith('stillopen-note:')) {
    await _showNoteAttachmentDialog(context, controller, attachment);
    return;
  }
  if (attachment.uri.startsWith('stillopen-metadata-only:')) {
    await _showAttachmentStatusDialog(
      context,
      title: attachment.label.ifBlank(_sourceTypeLabel(attachment.sourceType)),
      body:
          'Only this attachment history was restored. The original file bytes are not available in this backup.',
    );
    return;
  }
  final result = await OpenFilex.open(
    attachment.uri,
    type: controller.attachmentMimeType(attachment),
  );
  if (!context.mounted || result.type == ResultType.done) return;
  await _showAttachmentStatusDialog(
    context,
    title: 'Could not open attachment',
    body: 'The file is saved locally, but no app could open it.',
  );
}

Future<void> _showNoteAttachmentDialog(
  BuildContext context,
  StillOpenController controller,
  ItemAttachment attachment,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _NoteAttachmentEditDialog(
      controller: controller,
      attachment: attachment,
    ),
  );
}

class _NoteAttachmentEditDialog extends StatefulWidget {
  const _NoteAttachmentEditDialog({
    required this.controller,
    required this.attachment,
  });

  final StillOpenController controller;
  final ItemAttachment attachment;

  @override
  State<_NoteAttachmentEditDialog> createState() =>
      _NoteAttachmentEditDialogState();
}

class _NoteAttachmentEditDialogState extends State<_NoteAttachmentEditDialog> {
  late final TextEditingController noteController = TextEditingController(
    text: _noteAttachmentText(widget.attachment),
  );
  bool saving = false;

  @override
  void initState() {
    super.initState();
    noteController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: noteController.text.length,
    );
  }

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    final controller = widget.controller;
    final attachment = widget.attachment;
    final note = noteController.text;
    setState(() => saving = true);
    Navigator.pop(context);
    await controller.updateNoteAttachment(attachment, note);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit note attachment'),
      content: TextField(
        key: const Key('attachment_note_edit_input'),
        controller: noteController,
        autofocus: true,
        minLines: 4,
        maxLines: 10,
        decoration: const InputDecoration(hintText: 'Write the note'),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        FilledButton(onPressed: saving ? null : _save, child: Text('Save')),
      ],
    );
  }
}

Future<void> _showAttachmentStatusDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Done'),
        ),
      ],
    ),
  );
}

IconData _attachmentIcon(SourceType sourceType) => switch (sourceType) {
  SourceType.camera => Icons.photo_camera,
  SourceType.image || SourceType.sharedImage => Icons.image,
  SourceType.pdf => Icons.upload_file,
  SourceType.manual => Icons.article,
  SourceType.sharedText => Icons.notes,
  SourceType.sample => Icons.attach_file,
};

String _attachmentSubtitle(ItemAttachment attachment) {
  if (attachment.uri.startsWith('stillopen-note:')) return 'Note attachment';
  final type = attachment.sourceType == SourceType.manual
      ? 'File'
      : _sourceTypeLabel(attachment.sourceType);
  if (attachment.uri.startsWith('stillopen-metadata-only:')) {
    return '$type · metadata only';
  }
  return '$type · ${_uploadedLabel(attachment.createdAt)}';
}

String _uploadedLabel(int createdAt) {
  if (createdAt <= 0) return 'saved locally';
  final date = DateTime.fromMillisecondsSinceEpoch(createdAt);
  final month = const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][date.month - 1];
  return 'saved $month ${date.day}, ${date.year}';
}

String _noteAttachmentText(ItemAttachment attachment) {
  final uri = Uri.tryParse(attachment.uri);
  final data = uri?.queryParameters['data'];
  if (data != null && data.isNotEmpty) {
    try {
      return utf8.decode(base64Url.decode(data));
    } on Object {
      return attachment.label;
    }
  }
  return uri?.queryParameters['text'] ?? attachment.label;
}

SourceType _pickedFileSourceType(XFile file) {
  final mime = file.mimeType?.toLowerCase() ?? '';
  final extension = file.path.split('.').last.toLowerCase();
  if (mime.startsWith('image/') ||
      {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'}.contains(extension)) {
    return SourceType.image;
  }
  return mime == 'application/pdf' || extension == 'pdf'
      ? SourceType.pdf
      : SourceType.manual;
}

String _sourceTypeLabel(SourceType sourceType) => switch (sourceType) {
  SourceType.camera => 'Photo',
  SourceType.image || SourceType.sharedImage => 'Image',
  SourceType.pdf => 'File',
  SourceType.manual => 'Note',
  SourceType.sharedText => 'Text',
  SourceType.sample => 'Attachment',
};

String _fileNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash == -1 ? normalized : normalized.substring(slash + 1);
}

extension _ThemePreferenceLabels on AppThemePreference {
  String get displayLabel => switch (this) {
    AppThemePreference.system => 'System theme',
    AppThemePreference.light => 'Light theme',
    AppThemePreference.dark => 'Dark theme',
  };

  AppThemePreference get next => switch (this) {
    AppThemePreference.system => AppThemePreference.light,
    AppThemePreference.light => AppThemePreference.dark,
    AppThemePreference.dark => AppThemePreference.system,
  };
}

Future<void> _showTextEditDialog(
  BuildContext context,
  String title,
  String initial,
  Future<void> Function(String value) onSave,
) async {
  final textController = TextEditingController(text: initial);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: textController,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await onSave(textController.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text('Save'),
        ),
      ],
    ),
  );
}

class _DialogActionRow extends StatelessWidget {
  const _DialogActionRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.tint,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final tint = this.tint ?? _accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? tint.withValues(alpha: 0.16) : _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        surfaceTintColor: Colors.transparent,
        child: Semantics(
          label: label,
          button: true,
          container: true,
          explicitChildNodes: false,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              height: subtitle == null ? 42 : 58,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: subtitle == null ? 26 : 34,
                      height: subtitle == null ? 26 : 34,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        size: subtitle == null ? 16 : 19,
                        color: tint,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? tint : _text,
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              height: 1,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12,
                                height: 1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Material(
          color: _panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _border.withValues(alpha: 0.28)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsListRow extends StatelessWidget {
  const _SettingsListRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.tint,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final tint = this.tint ?? _accent;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: tint, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsInfoDialog extends StatelessWidget {
  const _SettingsInfoDialog({
    required this.title,
    required this.body,
    required this.onClose,
  });

  final String title;
  final String body;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(
        body,
        style: TextStyle(color: _text, fontSize: 14, height: 1.28),
      ),
      actions: [FilledButton(onPressed: onClose, child: Text('Done'))],
    );
  }
}

class _ExportImportDialog extends StatefulWidget {
  const _ExportImportDialog({required this.controller, required this.onClose});

  final StillOpenController controller;
  final VoidCallback onClose;

  @override
  State<_ExportImportDialog> createState() => _ExportImportDialogState();
}

class _ExportImportDialogState extends State<_ExportImportDialog> {
  String status = 'Export a backup file or import one from this device.';
  bool replace = false;

  Future<void> _exportBackupFile() async {
    const fileName = 'stillopen-backup.stillopen';
    final backupFile = XFile.fromData(
      Uint8List.fromList(utf8.encode(widget.controller.exportBackupJson())),
      mimeType: 'application/json',
      name: fileName,
    );
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [backupFile],
          fileNameOverrides: [fileName],
          subject: 'StillOpen backup',
        ),
      );
      if (!mounted) return;
      setState(() => status = 'Backup file ready to save or share.');
      final report = widget.controller.lastBackupExportReport;
      if (report != null) {
        setState(() => status = report.summary);
      }
    } on Object {
      if (!mounted) return;
      setState(() => status = 'Could not export the backup file.');
    }
  }

  Future<void> _importBackupFile() async {
    try {
      final file = await openFile(confirmButtonText: 'Import');
      if (file == null) {
        if (mounted) setState(() => status = 'No backup file selected.');
        return;
      }
      final count = await widget.controller.importBackupJson(
        await file.readAsString(),
        replace: replace,
      );
      if (!mounted) return;
      setState(() {
        status =
            widget.controller.lastImportReport?.summary ??
            'Imported $count items from backup file.';
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => status = 'Import failed: ${error.message}');
    } on Object {
      if (!mounted) return;
      setState(
        () => status =
            'Could not import backup. Local data was kept; please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Export / import'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(status, style: TextStyle(color: _muted, fontSize: 13)),
              const SizedBox(height: 12),
              SwitchListTile(
                value: replace,
                onChanged: (value) => setState(() => replace = value),
                title: Text('Replace local data on import'),
                subtitle: Text('Off imports a copy alongside existing items.'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 4),
              _DialogActionRow(
                label: 'Export backup file',
                subtitle: 'Save or share a StillOpen backup',
                icon: Icons.ios_share,
                tint: _accent,
                onTap: _exportBackupFile,
              ),
              _DialogActionRow(
                label: 'Import backup file',
                subtitle: 'Pick a StillOpen backup from this device',
                icon: Icons.file_open,
                tint: _accent,
                onTap: _importBackupFile,
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: widget.onClose, child: Text('Close'))],
    );
  }
}

class _ReminderDefaultsDialog extends StatefulWidget {
  const _ReminderDefaultsDialog({
    required this.preset,
    required this.hour,
    required this.minute,
    required this.onSave,
    required this.onClose,
  });

  final String preset;
  final int hour;
  final int minute;
  final void Function(String preset, int hour, int minute) onSave;
  final VoidCallback onClose;

  @override
  State<_ReminderDefaultsDialog> createState() =>
      _ReminderDefaultsDialogState();
}

class _ReminderDefaultsDialogState extends State<_ReminderDefaultsDialog> {
  late String preset = widget.preset;
  late double hour = widget.hour.toDouble();
  late double minute = widget.minute.toDouble();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reminder defaults'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['Today', 'Tomorrow', 'Next week']
                  .map(
                    (value) => ChoiceChip(
                      label: Text(value),
                      selected: preset == value,
                      onSelected: (_) => setState(() => preset = value),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Text('Hour · ${hour.round().toString().padLeft(2, '0')}'),
            Slider(
              key: const Key('reminder_default_hour'),
              value: hour,
              min: 0,
              max: 23,
              divisions: 23,
              label: hour.round().toString().padLeft(2, '0'),
              semanticFormatterCallback: (value) => '${value.round()} hours',
              onChanged: (value) => setState(() => hour = value),
            ),
            Text('Minute · ${minute.round().toString().padLeft(2, '0')}'),
            Slider(
              key: const Key('reminder_default_minute'),
              value: minute,
              min: 0,
              max: 59,
              divisions: 59,
              label: minute.round().toString().padLeft(2, '0'),
              semanticFormatterCallback: (value) => '${value.round()} minutes',
              onChanged: (value) => setState(() => minute = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onClose, child: Text('Cancel')),
        FilledButton(
          onPressed: () => widget.onSave(preset, hour.round(), minute.round()),
          child: Text('Save'),
        ),
      ],
    );
  }
}

IconData _domainIcon(DomainFilter filter) => switch (filter) {
  DomainFilter.medical => Icons.local_hospital_outlined,
  DomainFilter.school => Icons.school_outlined,
  DomainFilter.family => Icons.groups_outlined,
  DomainFilter.longTerm => Icons.event_repeat_outlined,
  DomainFilter.home => Icons.home_outlined,
  DomainFilter.shopping => Icons.shopping_bag_outlined,
  DomainFilter.money => Icons.account_balance_outlined,
  DomainFilter.documents => Icons.description_outlined,
  DomainFilter.all => Icons.tune,
};

IconData _categoryIconData(Category category) => switch (category) {
  Category.medical => Icons.local_hospital_outlined,
  Category.school => Icons.school_outlined,
  Category.shopping => Icons.shopping_bag_outlined,
  Category.money => Icons.account_balance_outlined,
  Category.documents => Icons.description_outlined,
  Category.home => Icons.home_outlined,
  Category.family => Icons.groups_outlined,
  Category.work => Icons.work_outline,
  Category.longTerm => Icons.event_repeat_outlined,
  Category.personal => Icons.person_outline,
  Category.other => Icons.radio_button_unchecked,
};

IconData _templateIcon(TemplateType template) => switch (template) {
  TemplateType.medicalClaim => Icons.local_hospital_outlined,
  TemplateType.schoolHomework || TemplateType.school => Icons.school_outlined,
  TemplateType.longTerm => Icons.event_repeat_outlined,
  TemplateType.home => Icons.home_outlined,
  TemplateType.shoppingReturn => Icons.shopping_bag_outlined,
  TemplateType.money => Icons.account_balance_outlined,
  TemplateType.document => Icons.description_outlined,
  TemplateType.quickNote => Icons.edit_note,
  TemplateType.other => Icons.more_horiz,
};

String _domainLabel(DomainFilter filter) => switch (filter) {
  DomainFilter.all => 'All',
  DomainFilter.medical => 'Medical',
  DomainFilter.school => 'School',
  DomainFilter.family => 'Family',
  DomainFilter.longTerm => 'Long-term',
  DomainFilter.home => 'Home',
  DomainFilter.shopping => 'Shopping',
  DomainFilter.money => 'Money',
  DomainFilter.documents => 'Documents',
};

String _sortLabel(SortMode mode) => switch (mode) {
  SortMode.smart => 'Smart',
  SortMode.date => 'Date',
  SortMode.updated => 'Updated',
  SortMode.category => 'Category',
};

String _templateLabel(TemplateType template) => switch (template) {
  TemplateType.quickNote => 'Quick note',
  TemplateType.medicalClaim => 'Medical claim',
  TemplateType.schoolHomework => 'School homework',
  TemplateType.school => 'School item',
  TemplateType.longTerm => 'Long-term reminder',
  TemplateType.home => 'Home / warranty',
  TemplateType.shoppingReturn => 'Shopping / return',
  TemplateType.money => 'Money / bill',
  TemplateType.document => 'Document',
  TemplateType.other => 'Other',
};

String _templateDescription(TemplateType template) => switch (template) {
  TemplateType.quickNote => 'Fast capture without extra fields',
  TemplateType.medicalClaim => 'Invoice, claim, response, reimbursement',
  TemplateType.schoolHomework => 'Homework with due date and subject',
  TemplateType.school => 'School forms, trips, fees, and events',
  TemplateType.longTerm => 'Recurring responsibility until booked',
  TemplateType.home => 'Warranty, repair, or home follow-up',
  TemplateType.shoppingReturn => 'Return, refund, or merchant response',
  TemplateType.money => 'Bill, payment, or money follow-up',
  TemplateType.document => 'Proof or document to keep findable',
  TemplateType.other => 'General open item',
};

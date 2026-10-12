import 'package:clock/clock.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import 'diagnostics.dart';
import 'attachment_paths.dart';
import 'date_logic.dart';
import 'models.dart';
import 'recurrence.dart';
import 'rules.dart';
import 'step_templates.dart';

typedef AttachmentDirectoryProvider = Future<Directory> Function();

abstract class ReminderScheduler {
  Future<void> requestPermissions();
  Future<void> schedule(StillOpenItem item, DateTime when);
  Future<void> cancel(int itemId);
  Future<void> cancelAll();
}

abstract interface class ReminderAvailability {
  Future<bool?> notificationsAllowed();
  Future<void> openNotificationSettings();
}

class ReminderPermissionDenied implements Exception {
  const ReminderPermissionDenied();
}

class CaptureReport {
  const CaptureReport({
    required this.filesUnavailable,
    this.saved = false,
    this.retryableFiles = 0,
  });
  final int filesUnavailable;
  final int retryableFiles;
  final bool saved;
  bool get complete => filesUnavailable == 0;
  bool get canAcknowledge => retryableFiles == 0;
}

class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<void> schedule(StillOpenItem item, DateTime when) async {}
  @override
  Future<void> cancel(int itemId) async {}
  @override
  Future<void> cancelAll() async {}
}

abstract class StillOpenStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

class SharedPreferencesStillOpenStore implements StillOpenStore {
  SharedPreferencesStillOpenStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
}

enum _AttachmentBackupStatus { included, metadataOnly, large, missing }

class _AttachmentBackupResult {
  const _AttachmentBackupResult({
    required this.json,
    required this.status,
    this.bytesIncluded = 0,
  });

  final Map<String, Object?> json;
  final _AttachmentBackupStatus status;
  final int bytesIncluded;
}

class _AttachmentImportEntry {
  _AttachmentImportEntry(this.json) : original = ItemAttachment.fromJson(json);

  final Map<String, Object?> json;
  final ItemAttachment original;

  String? get contentBase64 => json['contentBase64'] as String?;
  String? get fileName => json['fileName'] as String?;
}

class _AttachmentImportResult {
  const _AttachmentImportResult({
    required this.attachment,
    this.restored = false,
    this.metadataOnly = false,
  });

  final ItemAttachment attachment;
  final bool restored;
  final bool metadataOnly;
}

class ImportReport {
  const ImportReport({
    required this.itemsImported,
    required this.attachmentsImported,
    required this.attachmentsRestored,
    required this.attachmentsMetadataOnly,
    required this.schemaVersion,
    this.replaced = false,
  });

  final int itemsImported;
  final int attachmentsImported;
  final int attachmentsRestored;
  final int attachmentsMetadataOnly;
  final String schemaVersion;
  final bool replaced;

  bool get hasAttachmentGaps => attachmentsMetadataOnly > 0;

  String get summary {
    final attachmentPart = attachmentsImported == 0
        ? 'no attachments'
        : '$attachmentsImported attachments';
    final gapPart = attachmentsMetadataOnly == 0
        ? ''
        : ' · $attachmentsMetadataOnly metadata-only';
    return 'Imported $itemsImported items and $attachmentPart$gapPart';
  }

  Map<String, Object?> toJson() => {
    'items_imported': itemsImported,
    'attachments_imported': attachmentsImported,
    'attachments_restored': attachmentsRestored,
    'attachments_metadata_only': attachmentsMetadataOnly,
    'schema_version': schemaVersion,
    'replaced': replaced,
  };
}

class BackupExportReport {
  const BackupExportReport({
    required this.attachmentsIncluded,
    required this.attachmentsSkippedLarge,
    required this.attachmentsSkippedMissing,
    required this.totalBytesIncluded,
  });

  final int attachmentsIncluded;
  final int attachmentsSkippedLarge;
  final int attachmentsSkippedMissing;
  final int totalBytesIncluded;

  bool get hasSkippedAttachments =>
      attachmentsSkippedLarge > 0 || attachmentsSkippedMissing > 0;

  String get summary {
    if (!hasSkippedAttachments) return 'Backup file ready to save or share.';
    final parts = <String>[];
    if (attachmentsSkippedLarge > 0) {
      parts.add('$attachmentsSkippedLarge large files were not included');
    }
    if (attachmentsSkippedMissing > 0) {
      parts.add('$attachmentsSkippedMissing missing files were metadata-only');
    }
    return 'Backup created, but ${parts.join(' and ')}. The item history is still saved.';
  }

  Map<String, Object?> toJson() => {
    'attachments_included': attachmentsIncluded,
    'attachments_skipped_large': attachmentsSkippedLarge,
    'attachments_skipped_missing': attachmentsSkippedMissing,
    'total_bytes_included': totalBytesIncluded,
  };
}

class IncomingSharedFile {
  const IncomingSharedFile({
    required this.path,
    this.mimeType,
    this.name,
    this.isImage = false,
    this.metadataOnly = false,
    this.permanentlyUnavailable = false,
  });

  final String path;
  final String? mimeType;
  final String? name;
  final bool isImage;
  final bool metadataOnly;
  final bool permanentlyUnavailable;
}

class _ControllerMutation {
  _ControllerMutation(this.owner);
  final Object owner;
  final finished = Completer<void>();
  void release() {
    if (!finished.isCompleted) finished.complete();
  }
}

class StillOpenController extends ChangeNotifier {
  StillOpenController({
    StillOpenStore? store,
    AttachmentDirectoryProvider? attachmentDirectoryProvider,
    ReminderScheduler? reminderScheduler,
  }) : _store = store ?? SharedPreferencesStillOpenStore(),
       _reminderScheduler = reminderScheduler ?? const NoopReminderScheduler(),
       _attachmentDirectoryProvider =
           attachmentDirectoryProvider ?? _defaultAttachmentDirectory;

  static const _storageKey = 'stillopen_items_v1';
  static const _attachmentStorageKey = 'stillopen_attachments_v1';
  static const _settingsStorageKey = 'stillopen_settings_v1';
  static const _snapshotStorageKey = 'stillopen_snapshot_v2';
  static const defaultMaxExportAttachmentBytes = 10 * 1024 * 1024;
  static const defaultMaxExportTotalAttachmentBytes = 50 * 1024 * 1024;

  final StillOpenStore _store;
  final AttachmentDirectoryProvider _attachmentDirectoryProvider;
  final ReminderScheduler _reminderScheduler;
  ImportReport? lastImportReport;
  BackupExportReport? lastBackupExportReport;
  final Map<String, int> _handledIncomingShareKeys = {};
  final Object _mutationZoneKey = Object();
  Future<void> _mutationTail = Future.value();
  CaptureReport? lastCaptureReport;
  bool? notificationPermissionGranted;
  Future<void> _persistTail = Future.value();
  int _persistGeneration = 0;
  String? _committedSnapshot;
  Map<int, StillOpenItem> _committedReminderItems = {};
  bool _committedNotificationsEnabled = true;
  AttachmentPaths? _attachmentPaths;

  List<StillOpenItem> _items = const [];
  List<ItemAttachment> _attachments = const [];
  HomeTab selectedTab = HomeTab.open;
  SortMode sortMode = SortMode.smart;
  DomainFilter domainFilter = DomainFilter.all;
  PersonFilter personFilter = PersonFilter.all;
  FarFutureThreshold farFutureThreshold = FarFutureThreshold.oneMonth;
  bool showTemplateShortcuts = true;
  bool notificationsEnabled = true;
  AppThemePreference themePreference = AppThemePreference.system;
  String defaultReminderPreset = 'Tomorrow';
  int defaultReminderHour = 20;
  int defaultReminderMinute = 0;
  String query = '';
  int? selectedItemId;
  String? snackbarMessage;
  bool loaded = false;

  List<StillOpenItem> get items => List.unmodifiable(_items);
  List<ItemAttachment> get attachments => List.unmodifiable(_attachments);

  StillOpenItem? get selectedItem => selectedItemId == null
      ? null
      : _items.where((item) => item.id == selectedItemId).firstOrNull;

  ItemWithDetails? get selectedDetails {
    final item = selectedItem;
    if (item == null) return null;
    return ItemWithDetails(
      item: item,
      attachments: _attachments
          .where((attachment) => attachment.itemId == item.id)
          .toList(),
      timeline: _historyFor(item),
      steps: DefaultStepTemplates.forCategory(item.category)
          .map(
            (step) => ItemStepInstance(
              itemId: item.id,
              sourceTemplateId: step.id,
              title: step.title,
              type: step.type,
              appliesMode: step.appliesMode,
              defaultReminderLabel: step.defaultReminderLabel,
              sortOrder: step.sortOrder,
            ),
          )
          .toList(),
    );
  }

  List<StillOpenItem> get visibleItems {
    final filtered = _items
        .where(_matchesDomainFilter)
        .where(_matchesPersonFilter)
        .toList();
    return sortForMode(
      _searchWithAttachments(filterForTab(filtered, selectedTab), query),
      sortMode,
    );
  }

  int countForTab(HomeTab tab) => filterForTab(_items, tab).length;

  void refreshTimeStatuses() => notifyListeners();

  Future<T> _mutate<T>(Future<T> Function() action) {
    final current = Zone.current[_mutationZoneKey];
    if (current is _ControllerMutation &&
        current.owner == this &&
        !current.finished.isCompleted) {
      return action();
    }
    final generation = _persistGeneration;
    final scope = _ControllerMutation(this);
    final result = _mutationTail.then((_) async {
      try {
        if (generation != _persistGeneration) {
          throw StateError(
            'Concurrent save was aborted after an earlier failure.',
          );
        }
        return await runZoned(action, zoneValues: {_mutationZoneKey: scope});
      } finally {
        scope.release();
      }
    });
    _mutationTail = scope.finished.future;
    return result;
  }

  void _releaseMutation() {
    final scope = Zone.current[_mutationZoneKey];
    if (scope is _ControllerMutation && scope.owner == this) scope.release();
  }

  StillOpenItem _liveItem(StillOpenItem item) =>
      _items.where((current) => current.id == item.id).firstOrNull ??
      (throw StateError('This item no longer exists.'));

  List<TimelineEvent> _historyFor(StillOpenItem item) => item.history.isNotEmpty
      ? item.history
            .map(
              (event) => TimelineEvent(
                id: event.id,
                itemId: item.id,
                label: event.label,
                eventTimeText: event.eventTimeText,
                createdAt: event.createdAt,
              ),
            )
            .toList()
      : [
          TimelineEvent(
            itemId: item.id,
            label: 'Created in StillOpen',
            createdAt: item.createdAt,
          ),
          if (item.closedText.isNotEmpty)
            TimelineEvent(
              itemId: item.id,
              label: '${item.closedText} (historical record; time unavailable)',
            ),
        ];

  void _appendHistory(int itemId, String label) {
    _items = _items
        .map(
          (item) => item.id == itemId
              ? item.copyWith(
                  history: [
                    ..._historyFor(item),
                    TimelineEvent(
                      itemId: itemId,
                      label: label,
                      createdAt: clock.now().millisecondsSinceEpoch,
                    ),
                  ],
                )
              : item,
        )
        .toList();
  }

  StillOpenItem _initializeItem(StillOpenItem item) {
    final anchor = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    item = item.copyWith(
      dueAt:
          item.dueAt ??
          stillOpenDateEpoch(
            item.dueText,
            anchor: anchor,
            defaultHour: defaultReminderHour,
            defaultMinute: defaultReminderMinute,
          ),
      reminderAt:
          item.reminderAt ??
          stillOpenDateEpoch(
            item.reminderText,
            anchor: anchor,
            defaultHour: defaultReminderHour,
            defaultMinute: defaultReminderMinute,
          ),
      followUpAt:
          item.followUpAt ??
          stillOpenDateEpoch(
            item.followUpText,
            anchor: anchor,
            defaultHour: defaultReminderHour,
            defaultMinute: defaultReminderMinute,
          ),
      waitingSinceAt: item.state == ItemState.waiting ? item.createdAt : null,
      history: _historyFor(item),
    );
    if (item.state == ItemState.draft && item.reminderText.isEmpty) {
      final days = switch (defaultReminderPreset) {
        'Today' => 0,
        'Next week' => 7,
        _ => 1,
      };
      var when = DateTime(
        anchor.year,
        anchor.month,
        anchor.day + days,
        defaultReminderHour,
        defaultReminderMinute,
      );
      // The Today default must still yield a deliverable reminder late at night.
      if (!when.isAfter(anchor)) {
        when = DateTime(
          anchor.year,
          anchor.month,
          anchor.day + 1,
          defaultReminderHour,
          defaultReminderMinute,
        );
      }
      item = item.copyWith(
        reminderText: _dateTimeLabel(when, when.hour, when.minute),
        reminderAt: when.millisecondsSinceEpoch,
      );
    }
    return item;
  }

  List<StillOpenItem> _searchWithAttachments(
    List<StillOpenItem> items,
    String query,
  ) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return items;
    final matches = filterSearch(items, query).map((item) => item.id).toSet();
    for (final attachment in _attachments) {
      var searchable = attachment.label;
      if (attachment.uri.startsWith('stillopen-note:')) {
        final uri = Uri.tryParse(attachment.uri);
        try {
          final data = uri?.queryParameters['data'];
          searchable +=
              ' ${data == null ? uri?.queryParameters['text'] ?? '' : utf8.decode(base64Url.decode(data))}';
        } on FormatException {
          /* An older malformed note still has its label. */
        }
      }
      if (searchable.toLowerCase().contains(needle)) {
        matches.add(attachment.itemId);
      }
    }
    return items.where((item) => matches.contains(item.id)).toList();
  }

  String? attachmentMimeType(ItemAttachment attachment) {
    final declared = attachment.mimeType?.trim();
    if (declared != null &&
        declared.isNotEmpty &&
        declared != 'application/octet-stream') {
      return declared;
    }
    return _mimeForName(attachment.uri) ?? _mimeForName(attachment.label);
  }

  String? _mimeForName(String name) => const {
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'zip': 'application/zip',
    'mp3': 'audio/mpeg',
    'mp4': 'video/mp4',
    'html': 'text/html',
  }[_fileNameFromPath(name).toLowerCase().split('.').last];

  Future<void> refreshNotificationPermission() async {
    final scheduler = _reminderScheduler;
    try {
      notificationPermissionGranted = scheduler is ReminderAvailability
          ? await (scheduler as ReminderAvailability).notificationsAllowed()
          : null;
    } on Object {
      notificationPermissionGranted = null;
    }
    notifyListeners();
  }

  Future<void> reconcileNotifications() async {
    return _mutate(() async {
      // Wait for storage transactions, then let device permission I/O run
      // without blocking unrelated saves.
      _releaseMutation();
      await refreshNotificationPermission();
      if (!_committedNotificationsEnabled ||
          notificationPermissionGranted == false) {
        return;
      }
      for (final item in _committedReminderItems.values.toList()) {
        await _syncReminderForSafely(item, preserveElapsed: true);
      }
      notifyListeners();
    });
  }

  Future<void> openNotificationSettings() async {
    final scheduler = _reminderScheduler;
    if (scheduler is! ReminderAvailability) return;
    try {
      await (scheduler as ReminderAvailability).openNotificationSettings();
      await reconcileNotifications();
    } on Object {
      snackbarMessage = 'Could not open device notification settings.';
      notifyListeners();
    }
  }

  Future<void> load() async {
    return _mutate(() async {
      final snapshot = await _store.getString(_snapshotStorageKey);
      if (snapshot != null && snapshot.isNotEmpty) {
        final decoded = jsonDecode(snapshot);
        if (decoded is Map &&
            decoded['attachments'] is List &&
            (decoded['attachments'] as List).isNotEmpty) {
          _attachmentPaths = AttachmentPaths(
            await _attachmentDirectoryProvider(),
          );
        }
        _loadSnapshot(snapshot);
        _rememberCommittedSnapshot(snapshot);
        loaded = true;
        notifyListeners();
        await _syncAllRemindersSafely();
        return;
      }
      final raw = await _store.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _items = decoded
            .cast<Map<dynamic, dynamic>>()
            .map((json) => StillOpenItem.fromJson(json.cast<String, Object?>()))
            .toList();
      }
      final rawAttachments = await _store.getString(_attachmentStorageKey);
      if (rawAttachments != null && rawAttachments.isNotEmpty) {
        final decoded = jsonDecode(rawAttachments) as List<dynamic>;
        if (decoded.isNotEmpty) {
          _attachmentPaths = AttachmentPaths(
            await _attachmentDirectoryProvider(),
          );
        }
        _attachments = decoded
            .cast<Map<dynamic, dynamic>>()
            .map((json) => _attachmentFromStorage(json.cast<String, Object?>()))
            .toList();
      }
      final rawSettings = await _store.getString(_settingsStorageKey);
      if (rawSettings != null && rawSettings.isNotEmpty) {
        final decoded = jsonDecode(rawSettings) as Map<String, dynamic>;
        _loadSettings(decoded.cast<String, Object?>());
      }
      if (_upgradeLegacyRecurringItems()) await _persist();
      _rememberCommittedSnapshot(_snapshotJson());
      loaded = true;
      notifyListeners();
      await _syncAllRemindersSafely();
    });
  }

  void selectTab(HomeTab tab) {
    selectedTab = tab;
    selectedItemId = null;
    notifyListeners();
  }

  void selectSort(SortMode mode) {
    sortMode = mode;
    notifyListeners();
  }

  void selectDomainFilter(DomainFilter filter) {
    domainFilter = filter;
    notifyListeners();
  }

  void selectPersonFilter(PersonFilter filter) {
    personFilter = filter;
    notifyListeners();
  }

  Future<void> cycleFarFutureThreshold() async {
    return _mutate(() async {
      final values = FarFutureThreshold.values;
      farFutureThreshold =
          values[(values.indexOf(farFutureThreshold) + 1) % values.length];
      await _persist();
      notifyListeners();
    });
  }

  Future<void> setDefaultReminder(String preset, int hour, int minute) async {
    return _mutate(() async {
      defaultReminderPreset = preset;
      defaultReminderHour = hour;
      defaultReminderMinute = minute;
      await _persist();
      notifyListeners();
    });
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  Future<void> setTemplateShortcutsVisible(bool value) async {
    return _mutate(() async {
      showTemplateShortcuts = value;
      await _persist();
      notifyListeners();
    });
  }

  Future<void> setNotificationsEnabled(bool value) async {
    return _mutate(() async {
      notificationsEnabled = value;
      await _persist();
      if (value) {
        await _syncAllRemindersSafely();
      } else {
        await _cancelAllRemindersSafely();
      }
      await refreshNotificationPermission();
      if (value && notificationPermissionGranted == false) {
        snackbarMessage =
            'Saved, but notifications are blocked in device settings.';
      }
      notifyListeners();
    });
  }

  Future<void> setThemePreference(AppThemePreference value) async {
    return _mutate(() async {
      themePreference = value;
      await _persist();
      notifyListeners();
    });
  }

  void openDetails(int id) {
    selectedItemId = id;
    notifyListeners();
  }

  void closeDetails() {
    selectedItemId = null;
    notifyListeners();
  }

  Future<bool> quickAdd({
    required String title,
    bool tomorrow = false,
    bool highPriority = false,
    Category category = Category.other,
    bool categoryEdited = false,
  }) async {
    return _mutate(() async {
      final clean = title.trim();
      if (clean.isEmpty) return false;
      final resolvedCategory = categoryEdited
          ? category
          : StillOpenRules.suggestCategoryFromTitle(clean) ?? category;
      final now = clock.now().millisecondsSinceEpoch;
      final item = StillOpenItem(
        id: _nextId(),
        title: clean,
        state: ItemState.open,
        category: resolvedCategory,
        priority: highPriority ? Priority.high : Priority.normal,
        dueText: tomorrow ? 'Tomorrow' : '',
        dueAt: tomorrow
            ? DateTime(
                clock.now().year,
                clock.now().month,
                clock.now().day + 1,
                defaultReminderHour,
                defaultReminderMinute,
              ).millisecondsSinceEpoch
            : null,
        sourceType: SourceType.manual,
        assignedTo: 'Me',
        assignedToLabel: 'Me',
        categoryUserEdited: categoryEdited,
        dateUserEdited: !tomorrow,
        createdAt: now,
        updatedAt: now,
      );
      _items = [_initializeItem(item), ..._items];
      selectedTab = HomeTab.open;
      domainFilter = DomainFilter.all;
      personFilter = PersonFilter.all;
      selectedItemId = item.id;
      query = '';
      snackbarMessage = 'Saved to Open';
      await _persist();
      notifyListeners();
      return true;
    });
  }

  Future<void> createFromTemplate(TemplateType template) async {
    return _mutate(() async {
      final now = clock.now().millisecondsSinceEpoch;
      var item = _templateItem(template).copyWith(
        id: _nextId(),
        createdAt: now,
        updatedAt: now,
        assignedTo: 'Me',
        assignedToLabel: 'Me',
      );
      final rule = template == TemplateType.longTerm
          ? RecurrenceRule.parse(item.recurrenceHint)
          : null;
      if (rule != null) {
        item = _withNextReminder(item, rule.after(_reminderBase(clock.now())));
      }
      item = _initializeItem(item);
      _items = [item, ..._items];
      selectedTab = StillOpenRules.tabForState(item.state);
      domainFilter = DomainFilter.all;
      personFilter = PersonFilter.all;
      query = '';
      selectedItemId = item.id;
      snackbarMessage = 'Template started';
      await _persist();
      notifyListeners();
      if (item.reminderAt != null) await _syncReminderForSafely(item);
    });
  }

  Future<void> renameItem(StillOpenItem item, String title) async {
    return _mutate(() async {
      item = _liveItem(item);
      final clean = title.trim();
      if (clean.isEmpty || clean == item.title) return;
      final suggestedCategory = item.categoryUserEdited
          ? null
          : StillOpenRules.suggestCategoryFromTitle(clean);
      await _update(
        item.copyWith(
          title: clean,
          category: suggestedCategory ?? item.category,
          titleUserEdited: true,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Title updated',
      );
    });
  }

  Future<void> setCategory(StillOpenItem item, Category category) async {
    return _mutate(() async {
      item = _liveItem(item);
      await _update(
        item.copyWith(
          category: category,
          categoryUserEdited: true,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Category updated',
      );
    });
  }

  Future<void> setDate(StillOpenItem item, String value) async {
    return _mutate(() async {
      item = _liveItem(item);
      final when = stillOpenDateEpoch(
        value,
        defaultHour: defaultReminderHour,
        defaultMinute: defaultReminderMinute,
      );
      final label = item.templateType == TemplateType.longTerm && when != null
          ? _absoluteDateTimeLabel(DateTime.fromMillisecondsSinceEpoch(when))
          : value;
      await _update(
        item.copyWith(
          dueText: label,
          reminderText: label,
          dueAt: when,
          reminderAt: when,
          nextCycleAt: item.templateType == TemplateType.longTerm
              ? label
              : item.nextCycleAt,
          nextCycleAtEpoch: item.templateType == TemplateType.longTerm
              ? when
              : item.nextCycleAtEpoch,
          followUpAt: item.state == ItemState.waiting ? when : item.followUpAt,
          clearDueAt: when == null,
          clearReminderAt: when == null,
          clearNextCycleAtEpoch:
              item.templateType == TemplateType.longTerm && when == null,
          clearFollowUpAt: item.state == ItemState.waiting && when == null,
          followUpText: item.state == ItemState.waiting
              ? label
              : item.followUpText,
          dateUserEdited: true,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Date updated',
      );
    });
  }

  Future<void> setDateToday(StillOpenItem item) =>
      setPickedDueDateTime(item, clock.now());

  Future<void> setDateTomorrow(StillOpenItem item) =>
      setPickedDueDateTime(item, calendarDayAfter(clock.now(), 1));

  Future<void> setDateThisWeekend(StillOpenItem item) {
    final today = clock.now();
    final delta = (DateTime.saturday - today.weekday) >= 0
        ? DateTime.saturday - today.weekday
        : DateTime.daysPerWeek + DateTime.saturday - today.weekday;
    return setPickedDueDateTime(item, calendarDayAfter(today, delta));
  }

  Future<void> setPickedDueDateTime(
    StillOpenItem item,
    DateTime date, {
    int? hour,
    int? minute,
  }) async {
    return _mutate(() async {
      item = _liveItem(item);
      final selectedAt = DateTime(
        date.year,
        date.month,
        date.day,
        hour ?? defaultReminderHour,
        minute ?? defaultReminderMinute,
      );
      final label = item.templateType == TemplateType.longTerm
          ? _absoluteDateTimeLabel(selectedAt)
          : _dateTimeLabel(date, selectedAt.hour, selectedAt.minute);
      await _update(
        item.copyWith(
          dueText: label,
          reminderText: label,
          dueAt: selectedAt.millisecondsSinceEpoch,
          reminderAt: selectedAt.millisecondsSinceEpoch,
          nextCycleAt: item.templateType == TemplateType.longTerm
              ? label
              : item.nextCycleAt,
          nextCycleAtEpoch: item.templateType == TemplateType.longTerm
              ? selectedAt.millisecondsSinceEpoch
              : item.nextCycleAtEpoch,
          followUpAt: item.state == ItemState.waiting
              ? selectedAt.millisecondsSinceEpoch
              : item.followUpAt,
          followUpText: item.state == ItemState.waiting
              ? label
              : item.followUpText,
          dateUserEdited: true,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Date updated',
      );
    });
  }

  Future<void> setReminderToday(StillOpenItem item) =>
      setPickedReminder(item, clock.now());

  Future<void> setReminderTomorrow(StillOpenItem item) =>
      setPickedReminder(item, calendarDayAfter(clock.now(), 1));

  Future<void> setReminderThisWeekend(StillOpenItem item) {
    final today = clock.now();
    final delta = (DateTime.saturday - today.weekday) >= 0
        ? DateTime.saturday - today.weekday
        : DateTime.daysPerWeek + DateTime.saturday - today.weekday;
    return setPickedReminder(item, calendarDayAfter(today, delta));
  }

  Future<void> setPickedReminder(
    StillOpenItem item,
    DateTime date, {
    int? hour,
    int? minute,
  }) async {
    return _mutate(() async {
      item = _liveItem(item);
      final selectedAt = DateTime(
        date.year,
        date.month,
        date.day,
        hour ?? defaultReminderHour,
        minute ?? defaultReminderMinute,
      );
      final label = item.templateType == TemplateType.longTerm
          ? _absoluteDateTimeLabel(selectedAt)
          : _dateTimeLabel(date, selectedAt.hour, selectedAt.minute);
      await _update(
        item.copyWith(
          reminderText: label,
          reminderAt: selectedAt.millisecondsSinceEpoch,
          nextCycleAt: item.templateType == TemplateType.longTerm
              ? label
              : item.nextCycleAt,
          nextCycleAtEpoch: item.templateType == TemplateType.longTerm
              ? selectedAt.millisecondsSinceEpoch
              : item.nextCycleAtEpoch,
          followUpAt: item.state == ItemState.waiting
              ? selectedAt.millisecondsSinceEpoch
              : item.followUpAt,
          followUpText: item.state == ItemState.waiting
              ? label
              : item.followUpText,
          dateUserEdited: true,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Reminder set',
      );
    });
  }

  Future<void> setReminder(StillOpenItem item, String value) async {
    return _mutate(() async {
      item = _liveItem(item);
      final when = stillOpenDateEpoch(
        value,
        defaultHour: defaultReminderHour,
        defaultMinute: defaultReminderMinute,
      );
      final label = item.templateType == TemplateType.longTerm && when != null
          ? _absoluteDateTimeLabel(DateTime.fromMillisecondsSinceEpoch(when))
          : value;
      final removeRepeat =
          item.templateType == TemplateType.longTerm &&
          value.trim().isEmpty &&
          item.recurrenceHint.isNotEmpty;
      await _update(
        item.copyWith(
          reminderText: label,
          reminderAt: when,
          nextCycleAt: item.templateType == TemplateType.longTerm
              ? label
              : item.nextCycleAt,
          nextCycleAtEpoch: item.templateType == TemplateType.longTerm
              ? when
              : item.nextCycleAtEpoch,
          clearNextCycleAtEpoch:
              item.templateType == TemplateType.longTerm && when == null,
          recurrenceHint: removeRepeat ? '' : item.recurrenceHint,
          followUpAt: item.state == ItemState.waiting ? when : item.followUpAt,
          clearReminderAt: when == null,
          clearFollowUpAt: item.state == ItemState.waiting && when == null,
          followUpText: item.state == ItemState.waiting
              ? label
              : item.followUpText,
          dateUserEdited: true,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: removeRepeat
            ? 'Reminder and repeat cleared'
            : value.trim().isEmpty
            ? 'Reminder cleared'
            : when != null &&
                  !DateTime.fromMillisecondsSinceEpoch(
                    when,
                  ).isAfter(clock.now())
            ? 'Saved, but reminder date has passed.'
            : 'Reminder set',
      );
    });
  }

  Future<void> clearDate(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      await _update(
        item.copyWith(
          dueText: '',
          reminderText: '',
          recurrenceHint: item.templateType == TemplateType.longTerm
              ? ''
              : item.recurrenceHint,
          nextCycleAt: item.templateType == TemplateType.longTerm
              ? ''
              : item.nextCycleAt,
          clearNextCycleAtEpoch: item.templateType == TemplateType.longTerm,
          followUpText: '',
          clearDueAt: true,
          clearReminderAt: true,
          clearFollowUpAt: true,
          dateUserEdited: true,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Date cleared',
      );
    });
  }

  Future<void> clearReminder(StillOpenItem item) => setReminder(item, '');

  Future<void> setWaitingOn(StillOpenItem item, String value) async {
    return _mutate(() async {
      item = _liveItem(item);
      final clean = value.trim();
      final nextState = clean.isEmpty && item.state == ItemState.waiting
          ? ItemState.open
          : clean.isNotEmpty
          ? ItemState.waiting
          : item.state;
      await _update(
        item.copyWith(
          state: nextState,
          waitingOn: clean,
          waitingSinceText: clean.isEmpty
              ? ''
              : item.waitingSinceText.ifBlank('Just now'),
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: clean.isEmpty ? 'Waiting-on cleared' : 'Waiting-on updated',
      );
      selectedTab = StillOpenRules.tabForState(nextState);
    });
  }

  Future<void> setNote(StillOpenItem item, String value) async {
    return _mutate(() async {
      item = _liveItem(item);
      await _update(
        item.copyWith(
          notes: value.trim(),
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: value.trim().isEmpty ? 'Note cleared' : 'Note saved',
      );
    });
  }

  Future<void> addAttachment({
    required StillOpenItem item,
    required String uri,
    required String label,
    required SourceType sourceType,
    String? mimeType,
  }) async {
    return _mutate(() async {
      item = _liveItem(item);
      final cleanUri = uri.trim();
      if (cleanUri.isEmpty) return;
      final now = clock.now().millisecondsSinceEpoch;
      final id = _nextAttachmentId();
      final localUri = await _copyAttachmentToLocalStorage(
        id: id,
        uri: cleanUri,
        label: label,
      );
      if (localUri == null) {
        snackbarMessage = 'Could not save attachment locally';
        notifyListeners();
        return;
      }
      final attachment = ItemAttachment(
        id: id,
        itemId: item.id,
        uri: localUri,
        label: label.trim().ifBlank(sourceType.attachmentLabel),
        sourceType: sourceType,
        mimeType: mimeType ?? _mimeForName(cleanUri),
        createdAt: now,
      );
      _attachments = [attachment, ..._attachments];
      snackbarMessage = '${sourceType.attachmentLabel} attached';
      _appendHistory(item.id, snackbarMessage!);
      try {
        await _persist();
      } on Object {
        await _deleteLocalAttachmentFile(attachment);
        rethrow;
      }
      notifyListeners();
    });
  }

  Future<void> addNoteAttachment(StillOpenItem item, String note) async {
    return _mutate(() async {
      item = _liveItem(item);
      final clean = note.trim();
      if (clean.isEmpty) return;
      final label = _take(clean.split('\n').first.trim(), 40).ifBlank('Note');
      await addAttachment(
        item: item,
        uri: _noteAttachmentUri(clean),
        label: label,
        sourceType: SourceType.manual,
      );
    });
  }

  Future<bool> addSharedText(String text, {bool isUrl = false}) async {
    return _mutate(() async {
      return addSharedContent(text: text, isUrl: isUrl);
    });
  }

  Future<bool> addSharedFiles(List<IncomingSharedFile> files) async {
    return _mutate(() async {
      return addSharedContent(files: files);
    });
  }

  Future<bool> addSharedContent({
    String? text,
    bool isUrl = false,
    List<IncomingSharedFile> files = const [],
    String? eventId,
  }) async => (await captureSharedContent(
    text: text,
    isUrl: isUrl,
    files: files,
    eventId: eventId,
  )).saved;

  Future<CaptureReport> captureSharedContent({
    String? text,
    bool isUrl = false,
    List<IncomingSharedFile> files = const [],
    String? eventId,
  }) => _mutate(
    () => _addSharedContent(
      text: text,
      isUrl: isUrl,
      files: files,
      eventId: eventId,
    ),
  );

  Future<CaptureReport> _addSharedContent({
    String? text,
    required bool isUrl,
    required List<IncomingSharedFile> files,
    String? eventId,
  }) async {
    final clean = text?.trim() ?? '';
    final usable = files
        .where((file) => file.path.trim().isNotEmpty || file.metadataOnly)
        .toList();
    lastCaptureReport = null;
    if (clean.isEmpty && usable.isEmpty) {
      return const CaptureReport(filesUnavailable: 0);
    }
    final key = _incomingShareKey(clean, isUrl: isUrl, files: usable);
    final existing = eventId == null
        ? _items
              .where((item) => item.id == _handledIncomingShareKeys[key])
              .firstOrNull
        : _items
              .where((item) => item.incomingShareEventId == eventId)
              .firstOrNull;
    if (existing != null &&
        !_attachments.any(
          (a) =>
              a.itemId == existing.id &&
              a.uri.startsWith('stillopen-metadata-only:'),
        )) {
      lastCaptureReport = const CaptureReport(filesUnavailable: 0);
      return lastCaptureReport!;
    }
    final now = clock.now().millisecondsSinceEpoch;
    final firstFile = usable.firstOrNull;
    final item =
        existing ??
        _initializeItem(
          StillOpenItem(
            id: _nextId(),
            title: clean.isNotEmpty
                ? _incomingTextTitle(clean, isUrl: isUrl)
                : _incomingFileTitle(firstFile!, multiple: usable.length > 1),
            notes: clean,
            state: ItemState.draft,
            category:
                StillOpenRules.suggestCategoryFromTitle(clean) ??
                (usable.isEmpty ? Category.other : Category.documents),
            sourceType: clean.isNotEmpty
                ? SourceType.sharedText
                : _fileSourceType(firstFile!),
            sourceCaptureType: clean.isNotEmpty
                ? (isUrl ? SourceCaptureType.url : SourceCaptureType.sharedText)
                : _fileCaptureType(firstFile!),
            sourceLabel: _sharedContentSourceLabel(
              hasText: clean.isNotEmpty,
              isUrl: isUrl,
              fileCount: usable.length,
            ),
            sourceLabelConfidence: SourceLabelConfidence.systemDefault,
            incomingShareEventId: eventId,
            createdAt: now,
            updatedAt: now,
          ),
        );
    final prior = _attachments.where((a) => a.itemId == item.id).toList();
    final nextAttachments = <ItemAttachment>[];
    final copiedAttachments = <ItemAttachment>[];
    var nextId = _nextAttachmentId();
    var unavailable = 0;
    var retryable = 0;
    for (var index = 0; index < usable.length; index++) {
      final file = usable[index];
      final previous = prior
          .where((a) => a.captureFileIndex == index)
          .firstOrNull;
      if (previous != null &&
          !previous.uri.startsWith('stillopen-metadata-only:') &&
          (_attachmentFile(previous.uri)?.existsSync() ?? false)) {
        nextAttachments.add(previous);
        continue;
      }
      final id = previous?.id ?? nextId++;
      final label = (file.name?.trim() ?? '').ifBlank(
        _fileNameFromPath(
          file.path,
        ).ifBlank(file.isImage ? 'Shared image' : 'Shared file'),
      );
      final copied = file.metadataOnly
          ? null
          : await _copyAttachmentToLocalStorage(
              id: id,
              uri: file.path,
              label: label,
            );
      if (copied == null) {
        unavailable++;
        if (!file.permanentlyUnavailable) retryable++;
      }
      final attachment = ItemAttachment(
        id: id,
        itemId: item.id,
        uri: copied ?? _metadataOnlyAttachmentUri(id, file),
        label: label,
        sourceType: _fileSourceType(file),
        mimeType: file.mimeType ?? _mimeForName(file.path),
        captureFileIndex: index,
        createdAt: previous?.createdAt ?? now,
      );
      nextAttachments.add(attachment);
      if (copied != null) copiedAttachments.add(attachment);
    }
    // A file-only share with no recoverable bytes remains a failed capture.
    // Native metadata-only entries are intentional unavailable placeholders.
    if (existing == null &&
        clean.isEmpty &&
        copiedAttachments.isEmpty &&
        usable.isNotEmpty &&
        usable.every((file) => !file.metadataOnly)) {
      lastCaptureReport = CaptureReport(
        filesUnavailable: unavailable,
        retryableFiles: retryable,
      );
      snackbarMessage = 'Could not save shared file locally';
      notifyListeners();
      return lastCaptureReport!;
    }
    if (existing == null) _items = [item, ..._items];
    _attachments = [
      ...nextAttachments,
      ..._attachments.where(
        (a) => a.itemId != item.id || a.captureFileIndex == null,
      ),
    ];
    selectedTab = HomeTab.draft;
    domainFilter = DomainFilter.all;
    personFilter = PersonFilter.all;
    selectedItemId = item.id;
    query = '';
    snackbarMessage = unavailable == 0
        ? 'Shared item saved to Draft'
        : 'Shared item saved, but $unavailable attachment(s) unavailable. Retry or attach the files again.';
    try {
      await _persist();
    } on Object {
      for (final attachment in copiedAttachments) {
        await _deleteLocalAttachmentFile(attachment);
      }
      rethrow;
    }
    _handledIncomingShareKeys[key] = item.id;
    final report = CaptureReport(
      filesUnavailable: unavailable,
      retryableFiles: retryable,
      saved: true,
    );
    lastCaptureReport = report;
    if (item.reminderAt != null) await _syncReminderForSafely(item);
    notifyListeners();
    return report;
  }

  Future<void> renameAttachment(ItemAttachment attachment, String label) async {
    return _mutate(() async {
      final clean = label.trim();
      if (clean.isEmpty) return;
      _attachments = _attachments
          .map(
            (current) => current.id == attachment.id
                ? current.copyWith(label: clean)
                : current,
          )
          .toList();
      snackbarMessage = 'Attachment renamed';
      _appendHistory(attachment.itemId, snackbarMessage!);
      await _persist();
      notifyListeners();
    });
  }

  Future<void> updateNoteAttachment(
    ItemAttachment attachment,
    String note,
  ) async {
    return _mutate(() async {
      final clean = note.trim();
      if (clean.isEmpty || !attachment.uri.startsWith('stillopen-note:')) {
        return;
      }
      final label = _take(clean.split('\n').first.trim(), 40).ifBlank('Note');
      _attachments = _attachments
          .map(
            (current) => current.id == attachment.id
                ? current.copyWith(uri: _noteAttachmentUri(clean), label: label)
                : current,
          )
          .toList();
      snackbarMessage = 'Note updated';
      _appendHistory(attachment.itemId, snackbarMessage!);
      await _persist();
      notifyListeners();
    });
  }

  Future<void> deleteAttachment(ItemAttachment attachment) async {
    return _mutate(() async {
      _attachments = _attachments
          .where((current) => current.id != attachment.id)
          .toList();
      snackbarMessage = 'Attachment deleted';
      _appendHistory(attachment.itemId, snackbarMessage!);
      await _persist();
      await _deleteLocalAttachmentFile(attachment);
      notifyListeners();
    });
  }

  Future<void> makeOpen(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      selectedTab = HomeTab.open;
      await _update(
        item.copyWith(
          state: ItemState.open,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Moved to Open',
      );
    });
  }

  Future<void> markDone(
    StillOpenItem item, {
    ClosureReason closureReason = ClosureReason.handled,
  }) async {
    return _mutate(() async {
      item = _liveItem(item);
      final rule = item.templateType == TemplateType.longTerm
          ? RecurrenceRule.parse(item.recurrenceHint)
          : null;
      if (rule != null &&
          closureReason == ClosureReason.handled &&
          item.state != ItemState.done &&
          item.state != ItemState.ignored) {
        await completeLongTermCycle(item);
        return;
      }
      await _update(
        item.copyWith(
          state: ItemState.done,
          closedText: closureReason.displayLabel.ifBlank('Done just now'),
          closureReason: closureReason,
          waitingOn: '',
          followUpText: '',
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Moved to Done',
      );
    });
  }

  Future<void> reopen(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      selectedTab = HomeTab.open;
      await _update(
        item.copyWith(
          state: ItemState.open,
          closedText: '',
          closureReason: ClosureReason.none,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Reopened',
      );
    });
  }

  Future<void> moveForward(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      final next = StillOpenRules.forwardState(item.state);
      selectedTab = next == ItemState.done ? HomeTab.done : HomeTab.open;
      await _update(
        item.copyWith(
          state: next,
          closedText: next == ItemState.done ? 'Done just now' : '',
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: next == ItemState.done ? 'Moved to Done' : 'Moved to Open',
      );
    });
  }

  Future<void> moveBackward(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      final next = StillOpenRules.backwardState(item.state);
      selectedTab = next == ItemState.draft ? HomeTab.draft : HomeTab.open;
      await _update(
        item.copyWith(
          state: next,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: next == ItemState.draft ? 'Moved to Draft' : 'Moved to Open',
      );
    });
  }

  Future<void> markMedicalSubmitted(StillOpenItem item) => _updateClaimStage(
    item,
    ItemState.waiting,
    'Waiting for insurance response',
    'Insurance',
  );

  Future<void> markMedicalAppointmentBooked(StillOpenItem item) =>
      _updateClaimStage(
        item,
        ItemState.waiting,
        'Waiting for appointment',
        'Appointment / provider',
      );

  Future<void> markMedicalAppointmentDone(StillOpenItem item) =>
      _updateClaimStage(item, ItemState.open, 'Appointment done', '');

  Future<void> markMedicalResponseReceived(StillOpenItem item) =>
      _updateClaimStage(item, ItemState.open, 'Response received', '');

  Future<void> markMedicalForwarded(StillOpenItem item) => _updateClaimStage(
    item,
    ItemState.waiting,
    'Forwarded to private insurance',
    'Private insurance',
  );

  Future<void> markMedicalPrivateResponseReceived(StillOpenItem item) =>
      _updateClaimStage(item, ItemState.open, 'Private response received', '');

  Future<void> markMedicalReimbursed(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      selectedTab = HomeTab.done;
      await _update(
        item.copyWith(
          state: ItemState.done,
          claimStage: 'Reimbursed / closed',
          waitingOn: '',
          followUpText: '',
          closureReason: ClosureReason.reimbursed,
          closedText: ClosureReason.reimbursed.displayLabel,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Marked reimbursed',
      );
    });
  }

  Future<void> markLongTermBooked(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      selectedTab = HomeTab.open;
      await _update(
        item.copyWith(
          state: ItemState.waiting,
          waitingOn: item.waitingOn.ifBlank('Appointment / provider'),
          waitingSinceText: item.waitingSinceText.ifBlank('Just now'),
          lifecycleVariant: item.lifecycleVariant.ifBlank(
            'Recurring responsibility',
          ),
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Marked booked',
      );
    });
  }

  Future<void> setLongTermNextReminder(StillOpenItem item, String label) async {
    return _mutate(() async {
      item = _liveItem(item);
      final now = clock.now();
      final rule = RecurrenceRule.parse('every $label');
      final next = label == 'Tomorrow'
          ? DateTime(
              now.year,
              now.month,
              now.day + 1,
              defaultReminderHour,
              defaultReminderMinute,
            )
          : rule?.after(_reminderBase(now)) ?? _reminderDateTime(label);
      if (next == null) throw FormatException('Choose a dated reminder');
      await completeLongTermCycle(item, nextReminder: next);
    });
  }

  Future<void> setLongTermNextReminderFromRecurrence(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      await completeLongTermCycle(item);
    });
  }

  Future<void> completeLongTermCycle(
    StillOpenItem item, {
    DateTime? nextReminder,
  }) async {
    return _mutate(() async {
      item = _liveItem(item);
      final now = clock.now();
      final rule = RecurrenceRule.parse(item.recurrenceHint);
      final next = nextReminder ?? rule?.after(_reminderBase(now));
      if (next == null || !next.isAfter(now)) {
        throw FormatException(
          'Choose a future reminder or a supported recurrence',
        );
      }
      selectedTab = HomeTab.open;
      await _update(
        _withNextReminder(item, next).copyWith(
          state: ItemState.open,
          waitingOn: '',
          waitingSinceText: '',
          appointmentDateText: '',
          dueText: '',
          clearDueAt: true,
          followUpText: '',
          clearFollowUpAt: true,
          closedText: '',
          closureReason: ClosureReason.none,
          lastCycleCompletedAt: item.state == ItemState.done
              ? item.lastCycleCompletedAt
              : now.toIso8601String(),
          completedCycles:
              item.completedCycles + (item.state == ItemState.done ? 0 : 1),
          dateUserEdited: nextReminder != null,
          updatedAt: now.millisecondsSinceEpoch,
        ),
        message: 'Cycle complete · next reminder set',
      );
    });
  }

  Future<void> stopLongTermRecurrence(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      selectedTab = HomeTab.done;
      await _update(
        item.copyWith(
          state: ItemState.done,
          recurrenceHint: '',
          reminderText: '',
          clearReminderAt: true,
          nextCycleAt: '',
          clearNextCycleAtEpoch: true,
          waitingOn: '',
          waitingSinceText: '',
          followUpText: '',
          closedText: 'Done',
          closureReason: ClosureReason.handled,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: item.recurrenceHint.isEmpty
            ? 'Moved to Done'
            : 'Repeating stopped',
      );
    });
  }

  Future<void> setRecurrenceHint(StillOpenItem item, String label) async {
    return _mutate(() async {
      item = _liveItem(item);
      final clean = label.trim();
      final rule = RecurrenceRule.parse(clean);
      if (clean.isNotEmpty && rule == null) {
        throw FormatException(
          'Use Daily, Weekly, Monthly, Quarterly, Yearly, or Every N days/weeks/months/years',
        );
      }
      final now = clock.now();
      final existing = item.reminderAt == null
          ? _reminderDateTime(item.reminderText)
          : DateTime.fromMillisecondsSinceEpoch(item.reminderAt!);
      final keepExisting =
          existing != null &&
          item.state != ItemState.done &&
          (item.dateUserEdited || !existing.isAfter(now));
      final next = rule == null
          ? null
          : keepExisting
          ? existing
          : rule.after(_reminderBase(now));
      if (item.state == ItemState.done && rule != null) {
        selectedTab = HomeTab.open;
      }
      await _update(
        (next == null ? item : _withNextReminder(item, next)).copyWith(
          state: item.state == ItemState.done && rule != null
              ? ItemState.open
              : item.state,
          closedText: item.state == ItemState.done && rule != null
              ? ''
              : item.closedText,
          dueText: item.state == ItemState.done && rule != null
              ? ''
              : item.dueText,
          appointmentDateText: item.state == ItemState.done && rule != null
              ? ''
              : item.appointmentDateText,
          waitingOn: item.state == ItemState.done && rule != null
              ? ''
              : item.waitingOn,
          followUpText: item.state == ItemState.done && rule != null
              ? ''
              : item.followUpText,
          closureReason: item.state == ItemState.done && rule != null
              ? ClosureReason.none
              : item.closureReason,
          recurrenceHint: clean,
          nextCycleAt: rule == null ? '' : _absoluteDateTimeLabel(next!),
          clearNextCycleAtEpoch: rule == null,
          dateUserEdited: rule == null ? item.dateUserEdited : keepExisting,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: clean.isEmpty ? 'Recurrence cleared' : 'Recurrence updated',
      );
    });
  }

  Future<void> deleteItem(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      final itemAttachments = _attachments
          .where((attachment) => attachment.itemId == item.id)
          .toList();
      _items = _items.where((current) => current.id != item.id).toList();
      _attachments = _attachments
          .where((attachment) => attachment.itemId != item.id)
          .toList();
      if (selectedItemId == item.id) selectedItemId = null;
      snackbarMessage = 'Task deleted';
      await _persist();
      _handledIncomingShareKeys.removeWhere((_, value) => value == item.id);
      for (final attachment in itemAttachments) {
        await _deleteLocalAttachmentFile(attachment);
      }
      notifyListeners();
      await _cancelReminderSafely(item.id);
    });
  }

  Future<void> ignoreDraft(StillOpenItem item) async {
    return _mutate(() async {
      item = _liveItem(item);
      selectedTab = HomeTab.done;
      await _update(
        item.copyWith(
          state: ItemState.ignored,
          closedText: 'Ignored',
          closureReason: ClosureReason.notNeeded,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: 'Ignored',
      );
    });
  }

  Future<void> clearAllData() async {
    return _mutate(() async {
      final oldAttachments = _attachments.toList();
      _items = const [];
      _attachments = const [];
      selectedItemId = null;
      selectedTab = HomeTab.open;
      query = '';
      snackbarMessage = 'All data cleared';
      await _persist();
      _handledIncomingShareKeys.clear();
      for (final attachment in oldAttachments) {
        await _deleteLocalAttachmentFile(attachment);
      }
      await _cancelAllRemindersSafely();
      notifyListeners();
    });
  }

  String exportBackupJson({
    int maxPerAttachmentBytes = defaultMaxExportAttachmentBytes,
    int maxTotalAttachmentBytes = defaultMaxExportTotalAttachmentBytes,
  }) {
    var totalBytesIncluded = 0;
    var attachmentsIncluded = 0;
    var attachmentsSkippedLarge = 0;
    var attachmentsSkippedMissing = 0;
    final attachmentJson = <Map<String, Object?>>[];
    for (final attachment in _attachments) {
      final result = _attachmentBackupJson(
        attachment,
        maxPerAttachmentBytes: maxPerAttachmentBytes,
        remainingTotalBytes: maxTotalAttachmentBytes - totalBytesIncluded,
      );
      attachmentJson.add(result.json);
      switch (result.status) {
        case _AttachmentBackupStatus.included:
          attachmentsIncluded += 1;
          totalBytesIncluded += result.bytesIncluded;
        case _AttachmentBackupStatus.large:
          attachmentsSkippedLarge += 1;
        case _AttachmentBackupStatus.missing:
          attachmentsSkippedMissing += 1;
        case _AttachmentBackupStatus.metadataOnly:
          break;
      }
    }
    lastBackupExportReport = BackupExportReport(
      attachmentsIncluded: attachmentsIncluded,
      attachmentsSkippedLarge: attachmentsSkippedLarge,
      attachmentsSkippedMissing: attachmentsSkippedMissing,
      totalBytesIncluded: totalBytesIncluded,
    );
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'schema_version': 'stillopen_backup_v1',
      'exported_at': clock.now().toUtc().toIso8601String(),
      'items': _items.map((item) => item.toJson()).toList(),
      'attachments': attachmentJson,
      'settings': _settingsJson(),
    });
  }

  String exportDiagnosticsJson({
    Map<String, Object?> runtimeDiagnostics = const {},
  }) {
    final categoryCounts = <String, int>{};
    final stateCounts = <String, int>{};
    for (final item in _items) {
      categoryCounts[item.category.name] =
          (categoryCounts[item.category.name] ?? 0) + 1;
      stateCounts[item.state.name] = (stateCounts[item.state.name] ?? 0) + 1;
    }

    var readableAttachmentFiles = 0;
    var metadataOnlyAttachments = 0;
    var missingAttachmentFiles = 0;
    var noteAttachments = 0;
    for (final attachment in _attachments) {
      if (attachment.uri.startsWith('stillopen-note:')) {
        noteAttachments += 1;
        continue;
      }
      final file = _attachmentFile(attachment.uri);
      if (file == null) {
        metadataOnlyAttachments += 1;
      } else if (file.existsSync()) {
        readableAttachmentFiles += 1;
      } else {
        missingAttachmentFiles += 1;
      }
    }

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'schema_version': 'stillopen_diagnostics_v1',
      'exported_at': clock.now().toUtc().toIso8601String(),
      'privacy': {
        'redacted': true,
        'excludes_item_titles': true,
        'excludes_notes': true,
        'excludes_attachment_paths': true,
        'excludes_attachment_bytes': true,
      },
      'counts': {
        'items': _items.length,
        'attachments': _attachments.length,
        'readable_attachment_files': readableAttachmentFiles,
        'metadata_only_attachments': metadataOnlyAttachments,
        'missing_attachment_files': missingAttachmentFiles,
        'note_attachments': noteAttachments,
      },
      'category_counts': categoryCounts,
      'state_counts': stateCounts,
      'settings': {
        'theme': themePreference.name,
        'notifications_enabled': notificationsEnabled,
        'show_template_shortcuts': showTemplateShortcuts,
        'far_future_threshold': farFutureThreshold.name,
        'default_reminder_preset': defaultReminderPreset,
        'default_reminder_hour': defaultReminderHour,
        'default_reminder_minute': defaultReminderMinute,
      },
      if (lastImportReport != null) 'last_import': lastImportReport!.toJson(),
      if (lastBackupExportReport != null)
        'last_backup_export': lastBackupExportReport!.toJson(),
      if (runtimeDiagnostics.isNotEmpty)
        'runtime': StillOpenDiagnostics.redactForExport(runtimeDiagnostics),
    });
  }

  Future<int> importBackupJson(String raw, {bool replace = false}) async {
    return _mutate(() async {
      final decoded = jsonDecode(raw);
      final Map<String, Object?> backup;
      if (decoded is List) {
        backup = {'items': decoded};
      } else if (decoded is Map) {
        backup = decoded.cast<String, Object?>();
        final schemaVersion = backup['schema_version']?.toString();
        if (schemaVersion != null && schemaVersion != 'stillopen_backup_v1') {
          throw FormatException('Unsupported backup schema: $schemaVersion.');
        }
        if (backup['items'] is! List ||
            (backup.containsKey('attachments') &&
                backup['attachments'] is! List) ||
            (backup.containsKey('settings') && backup['settings'] is! Map)) {
          throw const FormatException(
            'Backup must contain an item list and valid sections.',
          );
        }
      } else {
        throw const FormatException(
          'Backup must be a JSON object or item list.',
        );
      }
      final importedItems = ((backup['items'] as List<dynamic>?) ?? const [])
          .cast<Map<dynamic, dynamic>>()
          .map((json) => StillOpenItem.fromJson(json.cast<String, Object?>()))
          .toList();
      final rawImportedAttachments =
          ((backup['attachments'] as List<dynamic>?) ?? const [])
              .cast<Map<dynamic, dynamic>>()
              .map(
                (json) => _AttachmentImportEntry(json.cast<String, Object?>()),
              )
              .toList();
      _validateGraph(
        importedItems,
        rawImportedAttachments.map((entry) => entry.original).toList(),
      );
      final importedAttachments = <ItemAttachment>[];
      var attachmentsRestored = 0;
      var attachmentsMetadataOnly = 0;
      final oldAttachments = _attachments.toList();
      final stage = await (await _localAttachmentDirectory()).createTemp(
        'import-',
      );
      try {
        if (replace) {
          _items = importedItems;
          for (final entry in rawImportedAttachments) {
            final imported = await _restoreImportedAttachment(
              entry,
              entry.original,
              stage,
            );
            importedAttachments.add(imported.attachment);
            if (imported.restored) {
              attachmentsRestored += 1;
            } else if (imported.metadataOnly) {
              attachmentsMetadataOnly += 1;
            }
          }
          _attachments = importedAttachments;
        } else {
          final nextItemId = _items.fold(
            0,
            (max, item) => item.id > max ? item.id : max,
          );
          final idMap = <int, int>{};
          _items = [
            ...importedItems.map((item) {
              final nextId = nextItemId + idMap.length + 1;
              idMap[item.id] = nextId;
              return item.copyWith(id: nextId);
            }),
            ..._items,
          ];
          final nextAttachmentId = _nextAttachmentId();
          var index = 0;
          for (final entry in rawImportedAttachments) {
            final finalAttachment = entry.original.copyWith(
              id: nextAttachmentId + index,
              itemId: idMap[entry.original.itemId]!,
            );
            final imported = await _restoreImportedAttachment(
              entry,
              finalAttachment,
              stage,
            );
            importedAttachments.add(imported.attachment);
            if (imported.restored) {
              attachmentsRestored += 1;
            } else if (imported.metadataOnly) {
              attachmentsMetadataOnly += 1;
            }
            index += 1;
          }
          _attachments = [...importedAttachments, ..._attachments];
        }
        final rawSettings = backup['settings'];
        if (rawSettings is Map) {
          _loadSettings(rawSettings.cast<String, Object?>());
        }
        _upgradeLegacyRecurringItems();
        selectedItemId = _items.firstOrNull?.id;
        selectedTab = selectedItem == null
            ? HomeTab.open
            : StillOpenRules.tabForState(selectedItem!.state);
        domainFilter = DomainFilter.all;
        personFilter = PersonFilter.all;
        query = '';
        final schemaVersion = backup['schema_version']?.toString() ?? 'legacy';
        lastImportReport = ImportReport(
          itemsImported: importedItems.length,
          attachmentsImported: importedAttachments.length,
          attachmentsRestored: attachmentsRestored,
          attachmentsMetadataOnly: attachmentsMetadataOnly,
          schemaVersion: schemaVersion,
          replaced: replace,
        );
        snackbarMessage = lastImportReport!.summary;
        await _persist();
      } on Object {
        if (stage.existsSync()) await stage.delete(recursive: true);
        if (_committedSnapshot != null) _loadSnapshot(_committedSnapshot!);
        rethrow;
      }
      if (replace) {
        _handledIncomingShareKeys.clear();
        for (final attachment in oldAttachments) {
          await _deleteLocalAttachmentFile(attachment);
        }
        await _cancelAllRemindersSafely();
      }
      notifyListeners();
      await _syncAllRemindersSafely();
      return importedItems.length;
    });
  }

  void clearSnackbar() {
    snackbarMessage = null;
  }

  bool _matchesDomainFilter(StillOpenItem item) {
    return switch (domainFilter) {
      DomainFilter.all => true,
      DomainFilter.medical => item.category == Category.medical,
      DomainFilter.school => item.category == Category.school,
      DomainFilter.family => item.category == Category.family,
      DomainFilter.longTerm =>
        item.category == Category.longTerm ||
            item.templateType == TemplateType.longTerm,
      DomainFilter.home => item.category == Category.home,
      DomainFilter.shopping => item.category == Category.shopping,
      DomainFilter.money => item.category == Category.money,
      DomainFilter.documents => item.category == Category.documents,
    };
  }

  bool _matchesPersonFilter(StillOpenItem item) {
    final haystack =
        '${item.personLabel} ${item.personTag} ${item.ownerLabel} ${item.assignedTo} ${item.assignedToLabel} ${item.sharedByName}'
            .toLowerCase();
    return switch (personFilter) {
      PersonFilter.all => true,
      PersonFilter.me => haystack.contains('me'),
      PersonFilter.partner => haystack.contains('partner'),
      PersonFilter.alex => haystack.contains('alex'),
      PersonFilter.max => haystack.contains('max'),
      PersonFilter.kids =>
        haystack.contains('kid') || item.category == Category.school,
      PersonFilter.family =>
        item.category == Category.family || haystack.contains('family'),
    };
  }

  int _nextId() =>
      _items.fold(0, (max, item) => item.id > max ? item.id : max) + 1;

  int _nextAttachmentId() =>
      _attachments.fold(0, (max, item) => item.id > max ? item.id : max) + 1;

  String _incomingShareKey(
    String text, {
    required bool isUrl,
    required List<IncomingSharedFile> files,
  }) {
    final parts = <String>[
      if (text.isNotEmpty) 'text:${isUrl ? 'url' : 'text'}:$text',
      if (files.isNotEmpty)
        'files:${files.map((file) => '${file.path}:${file.name ?? ''}:${file.mimeType ?? ''}:${file.metadataOnly}').join('|')}',
    ];
    return parts.join(';');
  }

  String _sharedContentSourceLabel({
    required bool hasText,
    required bool isUrl,
    required int fileCount,
  }) {
    if (hasText && fileCount > 0) {
      return isUrl ? 'Shared URL with files' : 'Shared text with files';
    }
    if (hasText) return isUrl ? 'Shared URL' : 'Shared text';
    return fileCount == 1 ? 'Shared file' : 'Shared files';
  }

  _AttachmentBackupResult _attachmentBackupJson(
    ItemAttachment attachment, {
    required int maxPerAttachmentBytes,
    required int remainingTotalBytes,
  }) {
    final json = attachment.toJson();
    final file = _attachmentFile(attachment.uri);
    if (file == null) {
      return _AttachmentBackupResult(
        json: json,
        status: attachment.uri.startsWith('stillopen-metadata-only:')
            ? _AttachmentBackupStatus.missing
            : _AttachmentBackupStatus.metadataOnly,
      );
    }
    if (!file.existsSync()) {
      return _AttachmentBackupResult(
        json: json,
        status: _AttachmentBackupStatus.missing,
      );
    }
    try {
      final size = file.lengthSync();
      if (size > maxPerAttachmentBytes || size > remainingTotalBytes) {
        return _AttachmentBackupResult(
          json: json,
          status: _AttachmentBackupStatus.large,
        );
      }
      json['contentBase64'] = base64Encode(file.readAsBytesSync());
      json['fileName'] = _backupFileName(attachment);
      return _AttachmentBackupResult(
        json: json,
        status: _AttachmentBackupStatus.included,
        bytesIncluded: size,
      );
    } on Object {
      return _AttachmentBackupResult(
        json: json,
        status: _AttachmentBackupStatus.missing,
      );
    }
  }

  Future<_AttachmentImportResult> _restoreImportedAttachment(
    _AttachmentImportEntry entry,
    ItemAttachment attachment,
    Directory stage,
  ) async {
    if (attachment.uri.startsWith('stillopen-note:')) {
      return _AttachmentImportResult(attachment: attachment);
    }
    if (entry.contentBase64 == null || entry.contentBase64!.isEmpty) {
      return _AttachmentImportResult(
        attachment: attachment.copyWith(
          uri: 'stillopen-metadata-only:${attachment.id}',
        ),
        metadataOnly: true,
      );
    }
    late final List<int> bytes;
    try {
      bytes = base64Decode(entry.contentBase64!);
    } on FormatException {
      return _AttachmentImportResult(
        attachment: attachment.copyWith(
          uri: 'stillopen-metadata-only:${attachment.id}',
        ),
        metadataOnly: true,
      );
    }
    final file = File(
      '${stage.path}/${attachment.id}_${_safeFileName(entry.fileName ?? attachment.label)}',
    );
    file.writeAsBytesSync(bytes, flush: true);
    return _AttachmentImportResult(
      attachment: attachment.copyWith(uri: file.path),
      restored: true,
    );
  }

  Future<String?> _copyAttachmentToLocalStorage({
    required int id,
    required String uri,
    required String label,
  }) async {
    if (uri.startsWith('stillopen-note:')) return uri;
    final source = _attachmentFile(uri);
    if (source == null) return null;
    try {
      final sourcePath = source.absolute.path;
      final directory = await _localAttachmentDirectory();
      final target = File(
        '${directory.path}/${id}_${_safeFileName(_fileNameFromPath(sourcePath).ifBlank(label))}',
      );
      if (sourcePath != target.absolute.path) {
        await source.copy(target.path);
      }
      return target.path;
    } on Object {
      return null;
    }
  }

  Future<void> _deleteLocalAttachmentFile(ItemAttachment attachment) async {
    final file = _attachmentFile(attachment.uri);
    if (file == null) return;
    try {
      final directory = await _localAttachmentDirectory();
      final directoryPath = directory.absolute.path;
      final filePath = file.absolute.path;
      if (!filePath.startsWith('$directoryPath${Platform.pathSeparator}')) {
        return;
      }
      if (file.existsSync()) await file.delete();
    } on Object {
      return;
    }
  }

  Future<Directory> _localAttachmentDirectory() async {
    final directory = await _attachmentDirectoryProvider();
    if (!directory.existsSync()) directory.createSync(recursive: true);
    _attachmentPaths = AttachmentPaths(directory);
    return directory;
  }

  File? _attachmentFile(String uri) {
    if (uri.startsWith('stillopen-note:')) return null;
    final parsed = Uri.tryParse(uri);
    if (parsed != null && parsed.hasScheme) {
      if (parsed.scheme != 'file') return null;
      return File(parsed.toFilePath());
    }
    return File(uri);
  }

  String _backupFileName(ItemAttachment attachment) {
    final file = _attachmentFile(attachment.uri);
    final pathName = file == null ? '' : file.uri.pathSegments.lastOrNull ?? '';
    return _safeFileName(pathName.ifBlank(attachment.label));
  }

  String _safeFileName(String value) {
    final clean = value
        .trim()
        .replaceAll(RegExp(r'[^\w.\- ]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return clean.ifBlank('attachment');
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    return parts.lastOrNull ?? '';
  }

  String _incomingTextTitle(String text, {required bool isUrl}) {
    if (text.isEmpty) return 'Shared text';
    final firstLine = text
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return _take(firstLine.ifBlank(isUrl ? 'Shared URL' : 'Shared text'), 80);
  }

  String _incomingFileTitle(IncomingSharedFile file, {required bool multiple}) {
    if (multiple) return 'Shared files';
    if (file.isImage) return 'Shared image';
    return (file.name?.trim().ifBlank('') ?? _fileNameFromPath(file.path))
        .ifBlank('Shared file');
  }

  String _metadataOnlyAttachmentUri(int id, IncomingSharedFile file) {
    return Uri(
      scheme: 'stillopen-metadata-only',
      host: 'shared-file',
      queryParameters: {
        'id': '$id',
        if (file.mimeType != null) 'type': file.mimeType!,
      },
    ).toString();
  }

  String _noteAttachmentUri(String note) {
    return Uri(
      scheme: 'stillopen-note',
      host: 'note',
      queryParameters: {
        'encoding': 'utf8-base64url',
        'data': base64Url.encode(utf8.encode(note)),
      },
    ).toString();
  }

  SourceType _fileSourceType(IncomingSharedFile file) {
    final mime = file.mimeType?.toLowerCase() ?? '';
    final name = (file.name ?? file.path).toLowerCase();
    if (file.isImage || mime.startsWith('image/')) {
      return SourceType.sharedImage;
    }
    if (mime == 'application/pdf' || name.endsWith('.pdf')) {
      return SourceType.pdf;
    }
    return SourceType.manual;
  }

  SourceCaptureType _fileCaptureType(IncomingSharedFile file) {
    final mime = file.mimeType?.toLowerCase() ?? '';
    final name = (file.name ?? file.path).toLowerCase();
    if (file.isImage || mime.startsWith('image/')) {
      return SourceCaptureType.sharedImage;
    }
    if (mime == 'application/pdf' || name.endsWith('.pdf')) {
      return SourceCaptureType.sharedPdf;
    }
    return SourceCaptureType.manual;
  }

  Future<void> _update(StillOpenItem item, {required String message}) async {
    final current = _liveItem(item);
    final enteringWait =
        item.state == ItemState.waiting &&
        (current.state != ItemState.waiting ||
            current.waitingOn != item.waitingOn);
    item = item.copyWith(
      waitingSinceAt: enteringWait
          ? clock.now().millisecondsSinceEpoch
          : current.waitingSinceAt,
      clearWaitingSinceAt: item.state != ItemState.waiting,
      waitingSinceText: item.state != ItemState.waiting
          ? ''
          : item.waitingSinceText,
      history: [
        ..._historyFor(current),
        TimelineEvent(
          itemId: item.id,
          label: message,
          createdAt: clock.now().millisecondsSinceEpoch,
        ),
      ],
      clearNextCycleAtEpoch:
          item.state == ItemState.done || item.state == ItemState.ignored,
      nextCycleAt:
          item.state == ItemState.done || item.state == ItemState.ignored
          ? ''
          : item.nextCycleAt,
    );
    _items = _items
        .map((existing) => existing.id == item.id ? item : existing)
        .toList();
    snackbarMessage = message;
    await _persist();
    await _syncReminderForSafely(
      item,
      preserveElapsed:
          current.reminderAt == item.reminderAt &&
          current.reminderText == item.reminderText,
    );
    notifyListeners();
  }

  Future<void> _syncAllReminders() async {
    _releaseMutation();
    if (!_committedNotificationsEnabled) {
      await _cancelAllRemindersSafely();
      return;
    }
    await _reminderScheduler.requestPermissions();
    await refreshNotificationPermission();
    for (final item in _committedReminderItems.values.toList()) {
      await _syncReminderFor(item, preserveElapsed: true);
    }
  }

  Future<void> _syncAllRemindersSafely() async {
    try {
      await _syncAllReminders();
    } on ReminderPermissionDenied {
      snackbarMessage =
          'Saved, but notifications are blocked in device settings.';
      await refreshNotificationPermission();
    } on Object catch (error, stackTrace) {
      StillOpenDiagnostics.instance.recordError(
        source: 'reminders',
        message: 'Reminder sync failed: ${error.runtimeType}',
        stack: stackTrace.toString(),
      );
    }
  }

  Future<void> _reconcileAfterCancel(int? itemId) async {
    if (!_committedNotificationsEnabled) return;
    final candidates = itemId == null
        ? _committedReminderItems.values.toList()
        : [_committedReminderItems[itemId]].whereType<StillOpenItem>().toList();
    for (final item in candidates) {
      if (item.state == ItemState.done ||
          item.state == ItemState.ignored ||
          item.reminderText.trim().isEmpty) {
        continue;
      }
      final when = item.reminderAt == null
          ? _reminderDateTime(
              item.reminderText,
              anchor: item.updatedAt > 0
                  ? DateTime.fromMillisecondsSinceEpoch(item.updatedAt)
                  : null,
            )
          : DateTime.fromMillisecondsSinceEpoch(item.reminderAt!);
      if (when != null && when.isAfter(clock.now())) {
        await _syncReminderForSafely(item);
      }
    }
  }

  Future<void> _cancelReminderSafely(int itemId) async {
    _releaseMutation();
    try {
      await _reminderScheduler.cancel(itemId);
      await _reconcileAfterCancel(itemId);
    } on Object catch (error, stackTrace) {
      StillOpenDiagnostics.instance.recordError(
        source: 'reminders',
        message: 'Reminder cancellation failed: ${error.runtimeType}',
        stack: stackTrace.toString(),
      );
    }
  }

  Future<void> _syncReminderForSafely(
    StillOpenItem item, {
    bool preserveElapsed = false,
  }) async {
    try {
      await _syncReminderFor(item, preserveElapsed: preserveElapsed);
      if (!preserveElapsed &&
          item.state != ItemState.done &&
          item.state != ItemState.ignored &&
          item.reminderAt != null &&
          item.reminderAt! <= clock.now().millisecondsSinceEpoch) {
        snackbarMessage = 'Saved, but reminder date has passed.';
      }
    } on ReminderPermissionDenied {
      snackbarMessage =
          'Saved, but notifications are blocked in device settings.';
      await refreshNotificationPermission();
    } on Object catch (error, stackTrace) {
      snackbarMessage =
          'Saved, but reminder could not be scheduled. Check notification settings.';
      StillOpenDiagnostics.instance.recordError(
        source: 'reminders',
        message: 'Reminder sync failed: ${error.runtimeType}',
        stack: stackTrace.toString(),
      );
    }
  }

  Future<void> _cancelAllRemindersSafely() async {
    _releaseMutation();
    try {
      await _reminderScheduler.cancelAll();
      await _reconcileAfterCancel(null);
    } on Object catch (error, stackTrace) {
      StillOpenDiagnostics.instance.recordError(
        source: 'reminders',
        message: 'Reminder cancellation failed: ${error.runtimeType}',
        stack: stackTrace.toString(),
      );
    }
  }

  Future<void> _syncReminderFor(
    StillOpenItem item, {
    bool preserveElapsed = false,
  }) async {
    _releaseMutation();
    final current = _committedReminderItems[item.id];
    if (current == null) {
      await _cancelReminderSafely(item.id);
      return;
    }
    item = current;
    if (!_committedNotificationsEnabled ||
        item.state == ItemState.done ||
        item.state == ItemState.ignored ||
        item.reminderText.trim().isEmpty) {
      await _cancelReminderSafely(item.id);
      return;
    }
    final when = item.reminderAt == null
        ? _reminderDateTime(
            item.reminderText,
            anchor: item.updatedAt > 0
                ? DateTime.fromMillisecondsSinceEpoch(item.updatedAt)
                : null,
          )
        : DateTime.fromMillisecondsSinceEpoch(item.reminderAt!);
    if (when == null) {
      await _cancelReminderSafely(item.id);
      return;
    }
    if (!when.isAfter(clock.now())) {
      if (!preserveElapsed) await _cancelReminderSafely(item.id);
      return;
    }
    await _reminderScheduler.schedule(item, when);
    final latest = _committedReminderItems[item.id];
    if (latest == null) {
      await _cancelReminderSafely(item.id);
    } else if (latest.state != item.state ||
        latest.title != item.title ||
        latest.reminderAt != item.reminderAt ||
        latest.reminderText != item.reminderText ||
        !_committedNotificationsEnabled) {
      await _syncReminderFor(latest);
    }
  }

  DateTime? _reminderDateTime(String label, {DateTime? anchor}) =>
      parseStillOpenDate(
        label,
        anchor: anchor,
        defaultHour: defaultReminderHour,
        defaultMinute: defaultReminderMinute,
      );

  DateTime _reminderBase(DateTime now) => DateTime(
    now.year,
    now.month,
    now.day,
    defaultReminderHour,
    defaultReminderMinute,
  );

  StillOpenItem _withNextReminder(StillOpenItem item, DateTime next) {
    final label = _absoluteDateTimeLabel(next);
    return item.copyWith(
      reminderText: label,
      reminderAt: next.millisecondsSinceEpoch,
      nextCycleAt: label,
      nextCycleAtEpoch: next.millisecondsSinceEpoch,
    );
  }

  bool _upgradeLegacyRecurringItems() {
    var changed = false;
    final now = clock.now();
    _items = _items.map((item) {
      final rule = item.templateType == TemplateType.longTerm
          ? RecurrenceRule.parse(item.recurrenceHint)
          : null;
      if (rule == null || item.state == ItemState.ignored) return item;
      final completed =
          item.state == ItemState.done &&
          item.closureReason == ClosureReason.completedThisCycle &&
          item.nextCycleAt.isNotEmpty;
      if (item.state == ItemState.done && !completed) return item;
      if (!completed && item.reminderAt != null) return item;
      final timestamp = completed ? item.updatedAt : item.createdAt;
      final anchor = timestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : now;
      final label = completed ? item.nextCycleAt : item.reminderText;
      final interval = RecurrenceRule.parse('every $label');
      final next = label.trim().toLowerCase() == 'tomorrow'
          ? DateTime(
              anchor.year,
              anchor.month,
              anchor.day + 1,
              defaultReminderHour,
              defaultReminderMinute,
            )
          : interval?.after(_reminderBase(anchor)) ??
                _reminderDateTime(label, anchor: anchor) ??
                (label.isEmpty ? rule.after(_reminderBase(anchor)) : null);
      if (next == null) return item;
      changed = true;
      return _withNextReminder(item, next).copyWith(
        state: completed ? ItemState.open : item.state,
        closedText: completed ? '' : item.closedText,
        closureReason: completed ? ClosureReason.none : item.closureReason,
        completedCycles: completed && item.completedCycles == 0
            ? 1
            : item.completedCycles,
        lastCycleCompletedAt: completed && item.lastCycleCompletedAt.isEmpty
            ? anchor.toIso8601String()
            : item.lastCycleCompletedAt,
      );
    }).toList();
    return changed;
  }

  Future<void> _updateClaimStage(
    StillOpenItem item,
    ItemState state,
    String stage,
    String waitingOn,
  ) async {
    return _mutate(() async {
      item = _liveItem(item);
      selectedTab = HomeTab.open;
      await _update(
        item.copyWith(
          state: state,
          claimStage: stage,
          waitingOn: waitingOn,
          waitingSinceText:
              state == ItemState.waiting &&
                  waitingOn.isNotEmpty &&
                  item.waitingSinceText.isEmpty
              ? 'Just now'
              : item.waitingSinceText,
          followUpText: state == ItemState.waiting && item.followUpText.isEmpty
              ? 'Pick date'
              : item.followUpText,
          updatedAt: clock.now().millisecondsSinceEpoch,
        ),
        message: stage,
      );
    });
  }

  Future<void> _persist() async {
    _validateGraph(_items, _attachments);
    final next = _snapshotJson();
    final generation = _persistGeneration;
    final result = _persistTail.then((_) async {
      if (generation != _persistGeneration) {
        _restoreAfterFailedSave();
        throw StateError(
          'Concurrent save was aborted after an earlier failure.',
        );
      }
      try {
        await _store.setString(_snapshotStorageKey, next);
        _rememberCommittedSnapshot(next);
      } on Object {
        _persistGeneration += 1;
        _restoreAfterFailedSave();
        rethrow;
      }
    });
    _persistTail = result.then((_) {}, onError: (Object _) {});
    await result;
  }

  void _rememberCommittedSnapshot(String raw) {
    final snapshot = jsonDecode(raw) as Map;
    _committedSnapshot = raw;
    _committedReminderItems = {
      for (final value in snapshot['items'] as List)
        (value as Map)['id'] as int: StillOpenItem.fromJson(
          value.cast<String, Object?>(),
        ),
    };
    _committedNotificationsEnabled =
        (snapshot['settings'] as Map)['notificationsEnabled'] as bool? ?? true;
  }

  void _restoreAfterFailedSave() {
    if (_committedSnapshot != null) _loadSnapshot(_committedSnapshot!);
    if (selectedItemId != null &&
        !_items.any((item) => item.id == selectedItemId)) {
      selectedItemId = null;
    }
    snackbarMessage = 'Could not save. Please try again.';
    notifyListeners();
  }

  String _snapshotJson() => jsonEncode({
    'schema_version': 'stillopen_snapshot_v2',
    'items': _items.map((item) => item.toJson()).toList(),
    'attachments': _attachments
        .map((item) => _attachmentPaths?.encode(item) ?? item.toJson())
        .toList(),
    'settings': _settingsJson(),
  });

  void _loadSnapshot(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['schema_version'] != 'stillopen_snapshot_v2' ||
        decoded['items'] is! List ||
        decoded['attachments'] is! List ||
        decoded['settings'] is! Map) {
      throw const FormatException('Invalid StillOpen local snapshot.');
    }
    final items = (decoded['items'] as List)
        .map(
          (value) =>
              StillOpenItem.fromJson((value as Map).cast<String, Object?>()),
        )
        .toList();
    final attachments = (decoded['attachments'] as List)
        .map(
          (value) =>
              _attachmentFromStorage((value as Map).cast<String, Object?>()),
        )
        .toList();
    _validateGraph(items, attachments);
    _items = items;
    _attachments = attachments;
    _loadSettings((decoded['settings'] as Map).cast<String, Object?>());
  }

  ItemAttachment _attachmentFromStorage(Map<String, Object?> json) =>
      _attachmentPaths?.decode(json) ?? ItemAttachment.fromJson(json);

  void _validateGraph(
    List<StillOpenItem> items,
    List<ItemAttachment> attachments,
  ) {
    final itemIds = <int>{};
    final attachmentIds = <int>{};
    for (final item in items) {
      if (item.id <= 0 || !itemIds.add(item.id)) {
        throw const FormatException(
          'Backup contains invalid or duplicate item IDs.',
        );
      }
    }
    for (final attachment in attachments) {
      if (attachment.id <= 0 ||
          !attachmentIds.add(attachment.id) ||
          !itemIds.contains(attachment.itemId)) {
        throw const FormatException(
          'Backup contains invalid attachment ownership or IDs.',
        );
      }
    }
  }

  Map<String, Object?> _settingsJson() => {
    'showTemplateShortcuts': showTemplateShortcuts,
    'notificationsEnabled': notificationsEnabled,
    'themePreference': themePreference.name,
    'defaultReminderPreset': defaultReminderPreset,
    'defaultReminderHour': defaultReminderHour,
    'defaultReminderMinute': defaultReminderMinute,
    'farFutureThreshold': farFutureThreshold.name,
  };

  void _loadSettings(Map<String, Object?> json) {
    showTemplateShortcuts =
        json['showTemplateShortcuts'] as bool? ?? showTemplateShortcuts;
    notificationsEnabled =
        json['notificationsEnabled'] as bool? ?? notificationsEnabled;
    themePreference = enumByName(
      AppThemePreference.values,
      json['themePreference'],
      themePreference,
    );
    defaultReminderPreset =
        json['defaultReminderPreset'] as String? ?? defaultReminderPreset;
    defaultReminderHour =
        (json['defaultReminderHour'] as num?)?.toInt() ?? defaultReminderHour;
    defaultReminderMinute =
        (json['defaultReminderMinute'] as num?)?.toInt() ??
        defaultReminderMinute;
    farFutureThreshold = enumByName(
      FarFutureThreshold.values,
      json['farFutureThreshold'],
      farFutureThreshold,
    );
  }

  StillOpenItem _templateItem(TemplateType template) {
    return switch (template) {
      TemplateType.medicalClaim => const StillOpenItem(
        title: 'Doctor invoice',
        state: ItemState.open,
        category: Category.medical,
        priority: Priority.high,
        templateType: TemplateType.medicalClaim,
        waitingOn: '',
        claimStage: 'Plan booking appointment',
        sourceLabel: 'Invoice',
        sourceLabelConfidence: SourceLabelConfidence.systemDefault,
        notes: 'Plan appointment, save invoice, then submit to insurance.',
      ),
      TemplateType.schoolHomework => const StillOpenItem(
        title: 'Math homework',
        state: ItemState.dueSoon,
        category: Category.school,
        templateType: TemplateType.schoolHomework,
        subjectLabel: 'Math',
        sourceLabel: 'WebUntis',
        sourceLabelConfidence: SourceLabelConfidence.systemDefault,
        dueText: 'Friday',
        notes: 'Homework, test, or school task to keep visible until Done.',
      ),
      TemplateType.school => const StillOpenItem(
        title: 'School form',
        state: ItemState.dueSoon,
        category: Category.school,
        templateType: TemplateType.school,
        dueText: 'Tomorrow',
        notes: 'School form, fee, or event to keep visible.',
      ),
      TemplateType.longTerm => const StillOpenItem(
        title: 'Book dentist check',
        state: ItemState.open,
        category: Category.longTerm,
        templateType: TemplateType.longTerm,
        lifecycleVariant: 'Recurring responsibility',
        recurrenceHint: 'Every 6 months',
        notes: 'Not a calendar event yet. Keep visible until booked.',
      ),
      TemplateType.home => const StillOpenItem(
        title: 'Home / warranty item',
        state: ItemState.open,
        category: Category.home,
        templateType: TemplateType.home,
        sourceLabel: 'Proof or warranty',
        notes: 'Keep the proof findable.',
      ),
      TemplateType.shoppingReturn => const StillOpenItem(
        title: 'Shopping return',
        state: ItemState.waiting,
        category: Category.shopping,
        templateType: TemplateType.shoppingReturn,
        waitingOn: 'Refund',
        notes: 'Waiting for refund or merchant response.',
      ),
      TemplateType.money => const StillOpenItem(
        title: 'Money / bill',
        state: ItemState.dueSoon,
        category: Category.money,
        templateType: TemplateType.money,
        notes: 'Bill or payment to keep visible.',
      ),
      TemplateType.document => const StillOpenItem(
        title: 'Documents / proof',
        state: ItemState.draft,
        category: Category.documents,
        templateType: TemplateType.document,
        sourceLabel: 'Document',
        notes: 'Saved for findability; move to Open if action is needed.',
      ),
      TemplateType.quickNote || TemplateType.other => const StillOpenItem(
        title: 'Open item',
        state: ItemState.open,
        category: Category.other,
        templateType: TemplateType.other,
        notes: 'Loose end to keep visible.',
      ),
    };
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}

Future<Directory> _defaultAttachmentDirectory() async =>
    Directory('${Directory.systemTemp.path}/stillopen_attachments')
      ..createSync(recursive: true);

extension _SourceTypeAttachmentLabel on SourceType {
  String get attachmentLabel => switch (this) {
    SourceType.camera => 'Photo',
    SourceType.image || SourceType.sharedImage => 'Image',
    SourceType.pdf => 'File',
    SourceType.manual => 'Note',
    SourceType.sharedText => 'Text',
    SourceType.sample => 'Attachment',
  };
}

String defaultNextReminderForRecurrence(String label) {
  final normalized = label.trim().toLowerCase();
  final preset = switch (normalized) {
    'daily' || 'every daily' || 'tomorrow' => 'Tomorrow',
    'weekly' || 'every weekly' || '1 week' => '1 week',
    'monthly' || 'every monthly' || '1 month' => '1 month',
    'quarterly' || 'every quarterly' || '3 months' => '3 months',
    'yearly' || 'every yearly' || '1 year' => '1 year',
    'every 6 months' || '6 months' => '6 months',
    _ => 'Pick date',
  };
  if (preset != 'Pick date') return preset;
  final rule = RecurrenceRule.parse(label);
  if (rule == null) return 'Pick date';
  final unit = switch (rule.unit) {
    RecurrenceUnit.day => 'day',
    RecurrenceUnit.week => 'week',
    RecurrenceUnit.month => 'month',
    RecurrenceUnit.year => 'year',
  };
  return '${rule.count} $unit${rule.count == 1 ? '' : 's'}';
}

String _dateTimeLabel(DateTime date, int hour, int minute) {
  final dateLabel = _dateLabel(date);
  final timeLabel =
      '${hour.clamp(0, 23).toString().padLeft(2, '0')}:${minute.clamp(0, 59).toString().padLeft(2, '0')}';
  return '$dateLabel $timeLabel';
}

String _absoluteDateTimeLabel(DateTime date) {
  const months = [
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
  ];
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${months[date.month - 1]} ${date.day}, ${date.year} $hour:$minute';
}

String _dateLabel(DateTime date) {
  final today = clock.now();
  final base = DateTime.utc(today.year, today.month, today.day);
  final target = DateTime.utc(date.year, date.month, date.day);
  final delta = target.difference(base).inDays;
  if (delta == 0) return 'Today';
  if (delta == 1) return 'Tomorrow';
  final saturdayDelta = (DateTime.saturday - today.weekday) >= 0
      ? DateTime.saturday - today.weekday
      : DateTime.daysPerWeek + DateTime.saturday - today.weekday;
  if (delta == saturdayDelta) return 'This weekend';
  const months = [
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
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _take(String value, int count) =>
    value.length <= count ? value : value.substring(0, count);

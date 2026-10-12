import 'package:clock/clock.dart';

import 'date_logic.dart';

enum ItemState {
  draft,
  open,
  dueSoon,
  waiting,
  missingInfo,
  done,
  overdue,
  ignored,
}

enum Category {
  personal,
  family,
  school,
  medical,
  longTerm,
  home,
  shopping,
  work,
  money,
  documents,
  other,
}

enum Priority { low, normal, high }

enum SourceType { manual, camera, image, sharedText, sharedImage, pdf, sample }

enum SourceLabelConfidence { userSet, inferred, systemDefault, unknown }

enum SourceCaptureType {
  manual,
  camera,
  pickedImage,
  sharedImage,
  sharedText,
  sharedPdf,
  url,
  sample,
}

enum TemplateType {
  quickNote,
  medicalClaim,
  schoolHomework,
  school,
  longTerm,
  home,
  shoppingReturn,
  money,
  document,
  other,
}

enum ClosureReason {
  none,
  handled,
  submitted,
  reimbursed,
  skipped,
  expired,
  notNeeded,
  completedThisCycle,
  proofOnly,
  other,
}

enum StepType { proof, action, waiting, reminder, payment, note, finalStep }

enum AppliesMode { always, askPerItem, optional }

enum HomeTab { draft, open, done }

enum SortMode { smart, date, updated, category }

enum DomainFilter {
  all,
  medical,
  school,
  family,
  longTerm,
  home,
  shopping,
  money,
  documents,
}

enum PersonFilter { all, me, partner, alex, max, kids, family }

enum AppThemePreference { system, light, dark }

enum FarFutureThreshold {
  twoWeeks('2 weeks', 14),
  oneMonth('1 month', 31),
  threeMonths('3 months', 93),
  never('Never', null);

  const FarFutureThreshold(this.label, this.days);
  final String label;
  final int? days;
}

class StillOpenItem {
  const StillOpenItem({
    this.id = 0,
    required this.title,
    this.notes = '',
    required this.state,
    required this.category,
    this.priority = Priority.normal,
    this.sourceType = SourceType.manual,
    this.sourceLabel = '',
    this.sourceLabelConfidence = SourceLabelConfidence.unknown,
    this.sourceCaptureType = SourceCaptureType.manual,
    this.templateType = TemplateType.quickNote,
    this.personTag = '',
    this.personLabel = '',
    this.ownerLabel = '',
    this.assignedTo = '',
    this.assignedToLabel = '',
    this.waitingOn = '',
    this.waitingSinceText = '',
    this.waitingSinceAt,
    this.lifecycleVariant = '',
    this.recurrenceHint = '',
    this.lastCycleCompletedAt = '',
    this.completedCycles = 0,
    this.claimStage = '',
    this.nextCycleAt = '',
    this.subjectLabel = '',
    this.appointmentDateText = '',
    this.privateInsuranceSkipped = false,
    this.skippedSteps = '',
    this.closureReason = ClosureReason.none,
    this.dueText = '',
    this.reminderText = '',
    this.followUpText = '',
    this.dueAt,
    this.reminderAt,
    this.followUpAt,
    this.nextCycleAtEpoch,
    this.closedText = '',
    this.ocrText = '',
    this.isSharedCopy = false,
    this.sharedByName = '',
    this.titleUserEdited = false,
    this.categoryUserEdited = false,
    this.dateUserEdited = false,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.history = const [],
    this.incomingShareEventId,
  });

  final int id;
  final String title;
  final String notes;
  final ItemState state;
  final Category category;
  final Priority priority;
  final SourceType sourceType;
  final String sourceLabel;
  final SourceLabelConfidence sourceLabelConfidence;
  final SourceCaptureType sourceCaptureType;
  final TemplateType templateType;
  final String personTag;
  final String personLabel;
  final String ownerLabel;
  final String assignedTo;
  final String assignedToLabel;
  final String waitingOn;
  final String waitingSinceText;
  final int? waitingSinceAt;
  final String lifecycleVariant;
  final String recurrenceHint;
  final String lastCycleCompletedAt;
  final int completedCycles;
  final String claimStage;
  final String nextCycleAt;
  final String subjectLabel;
  final String appointmentDateText;
  final bool privateInsuranceSkipped;
  final String skippedSteps;
  final ClosureReason closureReason;
  final String dueText;
  final String reminderText;
  final String followUpText;
  final int? dueAt;
  final int? reminderAt;
  final int? followUpAt;
  final int? nextCycleAtEpoch;
  final String closedText;
  final String ocrText;
  final bool isSharedCopy;
  final String sharedByName;
  final bool titleUserEdited;
  final bool categoryUserEdited;
  final bool dateUserEdited;
  final int createdAt;
  final int updatedAt;
  final List<TimelineEvent> history;
  final String? incomingShareEventId;

  StillOpenItem copyWith({
    int? id,
    String? title,
    String? notes,
    ItemState? state,
    Category? category,
    Priority? priority,
    SourceType? sourceType,
    String? sourceLabel,
    SourceLabelConfidence? sourceLabelConfidence,
    SourceCaptureType? sourceCaptureType,
    TemplateType? templateType,
    String? personTag,
    String? personLabel,
    String? ownerLabel,
    String? assignedTo,
    String? assignedToLabel,
    String? waitingOn,
    String? waitingSinceText,
    int? waitingSinceAt,
    bool clearWaitingSinceAt = false,
    String? lifecycleVariant,
    String? recurrenceHint,
    String? lastCycleCompletedAt,
    int? completedCycles,
    String? claimStage,
    String? nextCycleAt,
    String? subjectLabel,
    String? appointmentDateText,
    bool? privateInsuranceSkipped,
    String? skippedSteps,
    ClosureReason? closureReason,
    String? dueText,
    String? reminderText,
    String? followUpText,
    int? dueAt,
    int? reminderAt,
    int? followUpAt,
    int? nextCycleAtEpoch,
    bool clearDueAt = false,
    bool clearReminderAt = false,
    bool clearFollowUpAt = false,
    bool clearNextCycleAtEpoch = false,
    String? closedText,
    String? ocrText,
    bool? isSharedCopy,
    String? sharedByName,
    bool? titleUserEdited,
    bool? categoryUserEdited,
    bool? dateUserEdited,
    int? createdAt,
    int? updatedAt,
    List<TimelineEvent>? history,
    String? incomingShareEventId,
  }) {
    return StillOpenItem(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      state: state ?? this.state,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      sourceType: sourceType ?? this.sourceType,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      sourceLabelConfidence:
          sourceLabelConfidence ?? this.sourceLabelConfidence,
      sourceCaptureType: sourceCaptureType ?? this.sourceCaptureType,
      templateType: templateType ?? this.templateType,
      personTag: personTag ?? this.personTag,
      personLabel: personLabel ?? this.personLabel,
      ownerLabel: ownerLabel ?? this.ownerLabel,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToLabel: assignedToLabel ?? this.assignedToLabel,
      waitingOn: waitingOn ?? this.waitingOn,
      waitingSinceText: waitingSinceText ?? this.waitingSinceText,
      waitingSinceAt: clearWaitingSinceAt
          ? null
          : waitingSinceAt ?? this.waitingSinceAt,
      lifecycleVariant: lifecycleVariant ?? this.lifecycleVariant,
      recurrenceHint: recurrenceHint ?? this.recurrenceHint,
      lastCycleCompletedAt: lastCycleCompletedAt ?? this.lastCycleCompletedAt,
      completedCycles: completedCycles ?? this.completedCycles,
      claimStage: claimStage ?? this.claimStage,
      nextCycleAt: nextCycleAt ?? this.nextCycleAt,
      subjectLabel: subjectLabel ?? this.subjectLabel,
      appointmentDateText: appointmentDateText ?? this.appointmentDateText,
      privateInsuranceSkipped:
          privateInsuranceSkipped ?? this.privateInsuranceSkipped,
      skippedSteps: skippedSteps ?? this.skippedSteps,
      closureReason: closureReason ?? this.closureReason,
      dueText: dueText ?? this.dueText,
      reminderText: reminderText ?? this.reminderText,
      followUpText: followUpText ?? this.followUpText,
      dueAt: clearDueAt ? null : dueAt ?? this.dueAt,
      reminderAt: clearReminderAt ? null : reminderAt ?? this.reminderAt,
      followUpAt: clearFollowUpAt ? null : followUpAt ?? this.followUpAt,
      nextCycleAtEpoch: clearNextCycleAtEpoch
          ? null
          : nextCycleAtEpoch ?? this.nextCycleAtEpoch,
      closedText: closedText ?? this.closedText,
      ocrText: ocrText ?? this.ocrText,
      isSharedCopy: isSharedCopy ?? this.isSharedCopy,
      sharedByName: sharedByName ?? this.sharedByName,
      titleUserEdited: titleUserEdited ?? this.titleUserEdited,
      categoryUserEdited: categoryUserEdited ?? this.categoryUserEdited,
      dateUserEdited: dateUserEdited ?? this.dateUserEdited,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      history: history ?? this.history,
      incomingShareEventId: incomingShareEventId ?? this.incomingShareEventId,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'state': state.name,
    'category': category.name,
    'priority': priority.name,
    'sourceType': sourceType.name,
    'sourceLabel': sourceLabel,
    'sourceLabelConfidence': sourceLabelConfidence.name,
    'sourceCaptureType': sourceCaptureType.name,
    'templateType': templateType.name,
    'personTag': personTag,
    'personLabel': personLabel,
    'ownerLabel': ownerLabel,
    'assignedTo': assignedTo,
    'assignedToLabel': assignedToLabel,
    'waitingOn': waitingOn,
    'waitingSinceText': waitingSinceText,
    'waitingSinceAt': waitingSinceAt,
    'lifecycleVariant': lifecycleVariant,
    'recurrenceHint': recurrenceHint,
    'lastCycleCompletedAt': lastCycleCompletedAt,
    'completedCycles': completedCycles,
    'claimStage': claimStage,
    'nextCycleAt': nextCycleAt,
    'subjectLabel': subjectLabel,
    'appointmentDateText': appointmentDateText,
    'privateInsuranceSkipped': privateInsuranceSkipped,
    'skippedSteps': skippedSteps,
    'closureReason': closureReason.name,
    'dueText': dueText,
    'reminderText': reminderText,
    'followUpText': followUpText,
    'dueAt': dueAt,
    'reminderAt': reminderAt,
    'followUpAt': followUpAt,
    'nextCycleAtEpoch': nextCycleAtEpoch,
    'closedText': closedText,
    'ocrText': ocrText,
    'isSharedCopy': isSharedCopy,
    'sharedByName': sharedByName,
    'titleUserEdited': titleUserEdited,
    'categoryUserEdited': categoryUserEdited,
    'dateUserEdited': dateUserEdited,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'history': history.map((event) => event.toJson()).toList(),
    if (incomingShareEventId != null)
      'incomingShareEventId': incomingShareEventId,
  };

  factory StillOpenItem.fromJson(Map<String, Object?> json) {
    final updatedAt = (json['updatedAt'] as num?)?.toInt() ?? 0;
    final savedAt = updatedAt > 0
        ? updatedAt
        : (json['createdAt'] as num?)?.toInt() ?? 0;
    final anchor = savedAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(savedAt)
        : clock.now();
    int? migrated(String key, String label) {
      final raw = json[key];
      if (raw is num) return raw.toInt();
      if (raw is String && raw.trim().isNotEmpty) {
        final saved = DateTime.tryParse(raw);
        if (saved != null) return saved.millisecondsSinceEpoch;
      }
      return stillOpenDateEpoch(label, anchor: anchor);
    }

    return StillOpenItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? 'Open item',
      notes: json['notes'] as String? ?? '',
      state: enumByName(ItemState.values, json['state'], ItemState.open),
      category: enumByName(Category.values, json['category'], Category.other),
      priority: enumByName(Priority.values, json['priority'], Priority.normal),
      sourceType: enumByName(
        SourceType.values,
        json['sourceType'],
        SourceType.manual,
      ),
      sourceLabel: json['sourceLabel'] as String? ?? '',
      sourceLabelConfidence: enumByName(
        SourceLabelConfidence.values,
        json['sourceLabelConfidence'],
        SourceLabelConfidence.unknown,
      ),
      sourceCaptureType: enumByName(
        SourceCaptureType.values,
        json['sourceCaptureType'],
        SourceCaptureType.manual,
      ),
      templateType: enumByName(
        TemplateType.values,
        json['templateType'],
        TemplateType.quickNote,
      ),
      personTag: json['personTag'] as String? ?? '',
      personLabel: json['personLabel'] as String? ?? '',
      ownerLabel: json['ownerLabel'] as String? ?? '',
      assignedTo: json['assignedTo'] as String? ?? '',
      assignedToLabel: json['assignedToLabel'] as String? ?? '',
      waitingOn: json['waitingOn'] as String? ?? '',
      waitingSinceText: json['waitingSinceText'] as String? ?? '',
      waitingSinceAt: (json['waitingSinceAt'] as num?)?.toInt(),
      lifecycleVariant: json['lifecycleVariant'] as String? ?? '',
      recurrenceHint: json['recurrenceHint'] as String? ?? '',
      lastCycleCompletedAt: json['lastCycleCompletedAt'] as String? ?? '',
      completedCycles: (json['completedCycles'] as num?)?.toInt() ?? 0,
      claimStage: json['claimStage'] as String? ?? '',
      nextCycleAt: json['nextCycleAt'] as String? ?? '',
      subjectLabel: json['subjectLabel'] as String? ?? '',
      appointmentDateText: json['appointmentDateText'] as String? ?? '',
      privateInsuranceSkipped:
          json['privateInsuranceSkipped'] as bool? ?? false,
      skippedSteps: json['skippedSteps'] as String? ?? '',
      closureReason: enumByName(
        ClosureReason.values,
        json['closureReason'],
        ClosureReason.none,
      ),
      dueText: json['dueText'] as String? ?? '',
      reminderText: json['reminderText'] as String? ?? '',
      followUpText: json['followUpText'] as String? ?? '',
      dueAt: migrated('dueAt', json['dueText'] as String? ?? ''),
      reminderAt: migrated('reminderAt', json['reminderText'] as String? ?? ''),
      followUpAt: migrated('followUpAt', json['followUpText'] as String? ?? ''),
      nextCycleAtEpoch: migrated(
        'nextCycleAtEpoch',
        json['nextCycleAt'] as String? ?? '',
      ),
      closedText: json['closedText'] as String? ?? '',
      ocrText: json['ocrText'] as String? ?? '',
      isSharedCopy: json['isSharedCopy'] as bool? ?? false,
      sharedByName: json['sharedByName'] as String? ?? '',
      titleUserEdited: json['titleUserEdited'] as bool? ?? false,
      categoryUserEdited: json['categoryUserEdited'] as bool? ?? false,
      dateUserEdited: json['dateUserEdited'] as bool? ?? false,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      history: (json['history'] as List? ?? const [])
          .map(
            (event) =>
                TimelineEvent.fromJson((event as Map).cast<String, Object?>()),
          )
          .toList(),
      incomingShareEventId: json['incomingShareEventId'] as String?,
    );
  }
}

class ItemAttachment {
  const ItemAttachment({
    this.id = 0,
    required this.itemId,
    required this.uri,
    required this.label,
    required this.sourceType,
    this.mimeType,
    this.captureFileIndex,
    this.createdAt = 0,
  });

  final int id;
  final int itemId;
  final String uri;
  final String label;
  final SourceType sourceType;
  final String? mimeType;
  final int? captureFileIndex;
  final int createdAt;

  ItemAttachment copyWith({
    int? id,
    int? itemId,
    String? uri,
    String? label,
    SourceType? sourceType,
    String? mimeType,
    int? captureFileIndex,
    int? createdAt,
  }) => ItemAttachment(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    uri: uri ?? this.uri,
    label: label ?? this.label,
    sourceType: sourceType ?? this.sourceType,
    mimeType: mimeType ?? this.mimeType,
    captureFileIndex: captureFileIndex ?? this.captureFileIndex,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'itemId': itemId,
    'uri': uri,
    'label': label,
    'sourceType': sourceType.name,
    if (mimeType != null) 'mimeType': mimeType,
    if (captureFileIndex != null) 'captureFileIndex': captureFileIndex,
    'createdAt': createdAt,
  };

  factory ItemAttachment.fromJson(Map<String, Object?> json) => ItemAttachment(
    id: (json['id'] as num?)?.toInt() ?? 0,
    itemId: (json['itemId'] as num?)?.toInt() ?? 0,
    uri: json['uri'] as String? ?? '',
    label: json['label'] as String? ?? '',
    sourceType: enumByName(
      SourceType.values,
      json['sourceType'],
      SourceType.manual,
    ),
    mimeType: json['mimeType'] as String?,
    captureFileIndex: (json['captureFileIndex'] as num?)?.toInt(),
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
  );
}

class TimelineEvent {
  const TimelineEvent({
    this.id = 0,
    required this.itemId,
    required this.label,
    this.eventTimeText = '',
    this.createdAt = 0,
  });

  final int id;
  final int itemId;
  final String label;
  final String eventTimeText;
  final int createdAt;

  Map<String, Object?> toJson() => {'label': label, 'createdAt': createdAt};
  factory TimelineEvent.fromJson(Map<String, Object?> json) => TimelineEvent(
    itemId: 0,
    label: json['label'] as String? ?? 'Updated',
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
  );
}

class CategoryStepTemplate {
  const CategoryStepTemplate({
    required this.id,
    required this.category,
    required this.title,
    required this.type,
    required this.appliesMode,
    this.defaultReminderLabel = '',
    required this.sortOrder,
  });

  final String id;
  final Category category;
  final String title;
  final StepType type;
  final AppliesMode appliesMode;
  final String defaultReminderLabel;
  final int sortOrder;
}

class ItemStepInstance {
  const ItemStepInstance({
    this.id = 0,
    required this.itemId,
    this.sourceTemplateId = '',
    required this.title,
    required this.type,
    required this.appliesMode,
    this.defaultReminderLabel = '',
    required this.sortOrder,
  });

  final int id;
  final int itemId;
  final String sourceTemplateId;
  final String title;
  final StepType type;
  final AppliesMode appliesMode;
  final String defaultReminderLabel;
  final int sortOrder;
}

class ItemWithDetails {
  const ItemWithDetails({
    required this.item,
    this.attachments = const [],
    this.timeline = const [],
    this.steps = const [],
  });

  final StillOpenItem item;
  final List<ItemAttachment> attachments;
  final List<TimelineEvent> timeline;
  final List<ItemStepInstance> steps;
}

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  final value = name?.toString();
  final normalized = _normalizedEnumName(value);
  return values.cast<T?>().firstWhere(
        (entry) => _normalizedEnumName(entry?.name) == normalized,
        orElse: () => fallback,
      ) ??
      fallback;
}

String _normalizedEnumName(String? value) =>
    value?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') ?? '';

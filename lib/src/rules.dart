import 'package:clock/clock.dart';

// ignore_for_file: curly_braces_in_flow_control_structures, use_null_aware_elements

import 'dart:io';

import 'date_logic.dart';
import 'models.dart';

class StillOpenRules {
  static Category? suggestCategoryFromTitle(String title) {
    final text = title.toLowerCase();
    final scores = <Category, List<String>>{
      Category.school: [
        'school',
        'teacher',
        'class',
        'homework',
        'trip',
        'form',
        'schule',
        'klasse',
        'eltern',
        'hausubung',
        'hausübung',
      ],
      Category.medical: [
        'medical',
        'doctor invoice',
        'dentist invoice',
        'physiotherapy',
        'insurance claim',
        'reimbursement',
        'reimbursed',
        'arzt rechnung',
        'zahnarzt rechnung',
      ],
      Category.longTerm: [
        'long-term',
        'recurring',
        'annual',
        'renew',
        'renewal',
        'certificate',
        'next cycle',
        'maintenance',
        'registration',
      ],
      Category.shopping: [
        'refund',
        'return',
        'order',
        'package',
        'receipt',
        'retoure',
        'rucksendung',
        'rücksendung',
        'ruckerstattung',
        'rückerstattung',
      ],
      Category.money: [
        'invoice',
        'bill',
        'fee',
        'payment',
        'tax',
        'subscription',
        'rechnung',
        'betrag',
        'gebuhr',
        'gebühr',
        'zahlung',
      ],
      Category.home: [
        'warranty',
        'repair',
        'utility',
        'appliance',
        'home',
        'garantie',
        'reparatur',
        'strom',
        'gas',
      ],
      Category.documents: [
        'document',
        'pdf',
        'proof',
        'certificate copy',
        'passport copy',
        'file only',
      ],
      Category.work: [
        'work',
        'office',
        'client',
        'meeting',
        'job',
        'arbeit',
        'kunde',
        'termin',
      ],
      Category.family: [
        'family',
        'doctor',
        'dentist',
        'appointment',
        'kids',
        'arzt',
        'zahnarzt',
        'familie',
        'kind',
      ],
      Category.personal: [
        'personal',
        'passport',
        'license',
        'gym',
        'health',
        'personlich',
        'persönlich',
        'ausweis',
      ],
    };
    var bestScore = 0;
    Category? best;
    for (final entry in scores.entries) {
      final score = entry.value.where(text.contains).length;
      if (score > bestScore) {
        bestScore = score;
        best = entry.key;
      }
    }
    return bestScore > 0 ? best : null;
  }

  static ItemState forwardState(ItemState state) => switch (state) {
    ItemState.draft => ItemState.open,
    ItemState.open ||
    ItemState.dueSoon ||
    ItemState.waiting ||
    ItemState.missingInfo ||
    ItemState.overdue => ItemState.done,
    ItemState.done || ItemState.ignored => ItemState.done,
  };

  static ItemState backwardState(ItemState state) => switch (state) {
    ItemState.done || ItemState.ignored => ItemState.open,
    ItemState.open ||
    ItemState.dueSoon ||
    ItemState.waiting ||
    ItemState.missingInfo ||
    ItemState.overdue => ItemState.draft,
    ItemState.draft => ItemState.draft,
  };

  static HomeTab tabForState(ItemState state) => switch (state) {
    ItemState.draft => HomeTab.draft,
    ItemState.done || ItemState.ignored => HomeTab.done,
    _ => HomeTab.open,
  };

  static String dateLabelFromDate(DateTime date) =>
      '${_monthName(date.month)} ${date.day}';
}

extension CategoryLabels on Category {
  String get displayName => switch (this) {
    Category.longTerm => 'Long-term',
    _ => name[0].toUpperCase() + name.substring(1),
  };

  String get adjustStepsTitle => switch (this) {
    Category.medical => 'Medical claims',
    Category.longTerm => 'Long-term reminders',
    Category.shopping => 'Returns',
    Category.documents => 'Documents',
    Category.school => 'School',
    _ => displayName,
  };
}

extension ClosureReasonLabels on ClosureReason {
  String get displayLabel => switch (this) {
    ClosureReason.none => '',
    ClosureReason.handled => 'Done',
    ClosureReason.submitted => 'Submitted',
    ClosureReason.reimbursed => 'Reimbursed',
    ClosureReason.skipped => 'Skipped',
    ClosureReason.expired => 'Expired',
    ClosureReason.notNeeded => 'Not needed',
    ClosureReason.completedThisCycle => 'Completed this cycle',
    ClosureReason.proofOnly => 'Proof only',
    ClosureReason.other => 'Closed',
  };
}

extension StepLabels on StepType {
  String get displayLabel => switch (this) {
    StepType.proof => 'Proof',
    StepType.action => 'Action',
    StepType.waiting => 'Waiting',
    StepType.reminder => 'Reminder',
    StepType.payment => 'Payment',
    StepType.note => 'Note',
    StepType.finalStep => 'Finishes item',
  };
}

extension AppliesLabels on AppliesMode {
  String get displayLabel => switch (this) {
    AppliesMode.always => 'Always',
    AppliesMode.askPerItem => 'Ask per item',
    AppliesMode.optional => 'Optional',
  };
}

extension ItemPresentation on StillOpenItem {
  String get dateLabel {
    if (closedText.isNotEmpty) return closedText;
    if (dueText.isNotEmpty) return displayStillOpenDate(dueText, dueAt);
    if (reminderText.isNotEmpty)
      return displayStillOpenDate(reminderText, reminderAt);
    if (followUpText.isNotEmpty)
      return displayStillOpenDate(followUpText, followUpAt);
    return 'No date';
  }

  String get personDisplay => personLabel.isNotEmpty ? personLabel : personTag;

  String get closureDisplay {
    final reason = closureReason.displayLabel;
    if (reason.isNotEmpty) return reason;
    if (closedText.isEmpty) return '';
    return closedText[0].toUpperCase() + closedText.substring(1);
  }
}

List<StillOpenItem> filterForTab(List<StillOpenItem> items, HomeTab tab) {
  return items.where((item) {
    return switch (tab) {
      HomeTab.open => {
        ItemState.open,
        ItemState.dueSoon,
        ItemState.waiting,
        ItemState.missingInfo,
        ItemState.overdue,
      }.contains(item.state),
      HomeTab.draft => item.state == ItemState.draft,
      HomeTab.done => {ItemState.done, ItemState.ignored}.contains(item.state),
    };
  }).toList();
}

List<StillOpenItem> filterSearch(List<StillOpenItem> items, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return items.where((item) {
    return [
      item.title,
      item.notes,
      item.category.displayName,
      item.templateType.name,
      item.personTag,
      item.ownerLabel,
      item.assignedTo,
      item.waitingOn,
      item.claimStage,
      item.recurrenceHint,
      item.sourceLabel,
      item.ocrText,
      item.closedText,
    ].any((field) => field.toLowerCase().contains(q));
  }).toList();
}

List<StillOpenItem> sortForMode(
  List<StillOpenItem> items,
  SortMode mode, {
  DateTime? today,
}) {
  final sorted = [...items];
  switch (mode) {
    case SortMode.smart:
    case SortMode.date:
      sorted.sort((a, b) {
        final rank = sortDateRank(
          a,
          today: today,
        ).compareTo(sortDateRank(b, today: today));
        return rank != 0 ? rank : b.updatedAt.compareTo(a.updatedAt);
      });
    case SortMode.updated:
      sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case SortMode.category:
      sorted.sort((a, b) {
        final category = a.category.displayName.compareTo(
          b.category.displayName,
        );
        return category != 0 ? category : b.updatedAt.compareTo(a.updatedAt);
      });
  }
  return sorted;
}

int sortDateRank(StillOpenItem item, {DateTime? today}) {
  final ranks = [
    item.dueAt == null
        ? _dateRankFromLabel(item.dueText, today: today, item: item)
        : _dayRank(DateTime.fromMillisecondsSinceEpoch(item.dueAt!)),
    item.reminderAt == null
        ? _dateRankFromLabel(item.reminderText, today: today, item: item)
        : _dayRank(DateTime.fromMillisecondsSinceEpoch(item.reminderAt!)),
  ].whereType<int>();
  return ranks.isEmpty ? 0x7fffffff : ranks.reduce((a, b) => a < b ? a : b);
}

bool recurringReminderDue(StillOpenItem item, {DateTime? now}) {
  if (item.templateType != TemplateType.longTerm ||
      item.recurrenceHint.isEmpty ||
      {ItemState.done, ItemState.ignored}.contains(item.state))
    return false;
  final when = item.reminderAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(item.reminderAt!);
  return when != null && !when.isAfter(now ?? clock.now());
}

/// One clock-based classification for home grouping, chips and item details.
String? itemTimingAttentionLabel(StillOpenItem item, {DateTime? now}) {
  if ({
    ItemState.draft,
    ItemState.done,
    ItemState.ignored,
  }.contains(item.state)) {
    return null;
  }
  final current = now ?? clock.now();
  if (recurringReminderDue(item, now: current)) return 'Due for follow-up';
  final anchor = item.createdAt > 0
      ? DateTime.fromMillisecondsSinceEpoch(item.createdAt)
      : current;
  DateTime? date(int? epoch, String label) => epoch == null
      ? parseStillOpenDate(label, anchor: anchor)
      : DateTime.fromMillisecondsSinceEpoch(epoch);
  final due = date(item.dueAt, item.dueText);
  if (item.state != ItemState.waiting && due != null && !due.isAfter(current)) {
    return 'Overdue';
  }
  final followUp = date(item.followUpAt, item.followUpText);
  if (followUp != null && !followUp.isAfter(current)) {
    return 'Follow-up overdue';
  }
  final reminder = date(item.reminderAt, item.reminderText);
  if (reminder != null && !reminder.isAfter(current)) return 'Reminder due';
  return null;
}

DateTime? nextItemActionDate(StillOpenItem item) {
  final anchor = item.createdAt > 0
      ? DateTime.fromMillisecondsSinceEpoch(item.createdAt)
      : clock.now();
  final dates = [
    item.dueAt == null
        ? parseStillOpenDate(item.dueText, anchor: anchor)
        : DateTime.fromMillisecondsSinceEpoch(item.dueAt!),
    item.reminderAt == null
        ? parseStillOpenDate(item.reminderText, anchor: anchor)
        : DateTime.fromMillisecondsSinceEpoch(item.reminderAt!),
    item.followUpAt == null
        ? parseStillOpenDate(item.followUpText, anchor: anchor)
        : DateTime.fromMillisecondsSinceEpoch(item.followUpAt!),
  ].whereType<DateTime>().toList()..sort();
  return dates.firstOrNull;
}

bool itemNeedsAttention(StillOpenItem item) =>
    itemTimingAttentionLabel(item) != null ||
    {
      ItemState.dueSoon,
      ItemState.overdue,
      ItemState.missingInfo,
    }.contains(item.state) ||
    (item.state == ItemState.waiting &&
        (waitingNeedsFollowUp(item) ||
            followUpOverdue(item) ||
            waitingTooLong(item)));

String statusLabel(StillOpenItem item) {
  if (item.state == ItemState.draft && draftNeedsDecision(item))
    return 'Needs decision';
  if (item.state == ItemState.draft) return 'Draft';
  if ({ItemState.done, ItemState.ignored}.contains(item.state))
    return 'Findable';
  final timing = itemTimingAttentionLabel(item);
  if (timing != null) return timing;
  if (item.state == ItemState.waiting && followUpOverdue(item))
    return 'Follow-up overdue';
  if (item.state == ItemState.waiting && waitingTooLong(item))
    return 'Waiting too long';
  if (item.state == ItemState.waiting && waitingNeedsFollowUp(item))
    return 'Needs follow-up';
  if (item.state == ItemState.waiting) return 'Waiting';
  if (item.state == ItemState.missingInfo) return 'Missing info';
  if (item.state == ItemState.overdue) return 'Overdue';
  if (item.reminderText.isNotEmpty || item.followUpText.isNotEmpty)
    return 'Reminder set';
  if (item.sourceType == SourceType.sample) return 'Sample source';
  if (![SourceType.manual, SourceType.sharedText].contains(item.sourceType))
    return 'Source needs check';
  if (item.sourceLabel.isNotEmpty) return 'Source label';
  if (item.dueText.isNotEmpty && item.dueText != 'No date')
    return 'Needs reminder';
  return 'Needs date';
}

String rowMetaHint(StillOpenItem item) {
  String? closureValue() {
    if ({ItemState.done, ItemState.ignored}.contains(item.state) &&
        item.closureDisplay.isNotEmpty) {
      return item.closureDisplay.toLowerCase();
    }
    return null;
  }

  String sourceValue([String value = 'source noted']) {
    if (item.sourceType == SourceType.sample) return 'sample source';
    if (item.sourceLabel.isNotEmpty) return value.replaceAll('saved', 'label');
    if (item.sourceType == SourceType.manual) return 'manual';
    return 'source needs check';
  }

  String? timingValue() {
    if (item.state == ItemState.waiting) return 'waiting';
    if (item.followUpText.isNotEmpty) return 'follow-up set';
    if (item.reminderText.isNotEmpty) return 'reminder set';
    if (item.dueText.isNotEmpty && item.dueText != 'No date')
      return 'due ${displayStillOpenDate(item.dueText, item.dueAt).toLowerCase()}';
    if (item.state == ItemState.done) return 'findable';
    return null;
  }

  final closure = closureValue();
  final parts = switch (item.templateType) {
    TemplateType.medicalClaim => [
      'Medical',
      if (closure != null) closure,
      if (closure == null &&
          (item.state == ItemState.waiting || item.waitingOn.isNotEmpty))
        'waiting',
      if (closure == null &&
          item.state != ItemState.waiting &&
          item.waitingOn.isEmpty)
        sourceValue('invoice saved'),
      if (closure != null) sourceValue('source saved'),
    ],
    TemplateType.schoolHomework => [
      'School',
      item.subjectLabel.isEmpty ? 'homework' : item.subjectLabel,
      timingValue(),
    ],
    TemplateType.school => ['School', sourceValue(), timingValue()],
    TemplateType.longTerm => [
      'Long-term',
      item.nextCycleAt.isNotEmpty ? 'reminder set' : closure ?? timingValue(),
    ],
    TemplateType.shoppingReturn => [
      'Shopping',
      closure ?? sourceValue('proof saved'),
      timingValue(),
    ],
    TemplateType.home => ['Home', closure ?? sourceValue()],
    TemplateType.money => ['Money', timingValue() ?? sourceValue()],
    TemplateType.document => [
      'Documents',
      closure ?? sourceValue('proof saved'),
    ],
    TemplateType.quickNote => [
      item.category.displayName,
      if (item.assignedTo.isNotEmpty)
        'assigned to ${item.assignedTo}'
      else if (item.isSharedCopy)
        'shared by ${item.sharedByName.isEmpty ? 'Shared copy' : item.sharedByName}'
      else
        'loose note',
      timingValue(),
    ],
    TemplateType.other => [
      item.category.displayName,
      if (item.assignedTo.isNotEmpty)
        'assigned to ${item.assignedTo}'
      else if (item.isSharedCopy)
        'shared by ${item.sharedByName.isEmpty ? 'Shared copy' : item.sharedByName}'
      else if (item.sourceLabel.isNotEmpty)
        'source label'
      else if (item.sourceType == SourceType.manual)
        'loose end'
      else
        item.sourceType.name.toLowerCase(),
      timingValue(),
    ],
  };
  return parts.whereType<String>().where((part) => part.isNotEmpty).join(' · ');
}

String minimalCategoryLabel(StillOpenItem item) => switch (item.templateType) {
  TemplateType.medicalClaim => 'Medical claim',
  TemplateType.schoolHomework => 'School homework',
  TemplateType.school => 'School item',
  TemplateType.longTerm => 'Long-term reminder',
  TemplateType.shoppingReturn => 'Return',
  TemplateType.money => 'Money',
  TemplateType.document => 'Document',
  TemplateType.home => 'Home',
  TemplateType.quickNote || TemplateType.other => item.category.displayName,
};

bool isMedicalWorkflowItem(StillOpenItem item) =>
    item.templateType == TemplateType.medicalClaim ||
    item.category == Category.medical ||
    item.claimStage.trim().isNotEmpty;

String minimalStatusSentence(StillOpenItem item) {
  if ({ItemState.done, ItemState.ignored}.contains(item.state)) return 'Done';
  final timing = itemTimingAttentionLabel(item);
  if (timing != null) return timing;
  if (isMedicalWorkflowItem(item)) {
    final stage = item.claimStage.toLowerCase();
    if (item.privateInsuranceSkipped ||
        stage.contains('private response') ||
        stage.contains('reimbursed'))
      return 'Ready to close';
    if (stage.contains('response received')) return 'Response received';
    if (stage.contains('forwarded'))
      return 'Waiting for private insurance response';
    if (stage.contains('waiting for insurance') ||
        stage.contains('submitted') ||
        item.waitingOn.toLowerCase().contains('insurance') ||
        item.state == ItemState.waiting) {
      return 'Waiting for insurance response';
    }
    return 'Needs submission';
  }
  if (item.templateType == TemplateType.shoppingReturn &&
      item.state == ItemState.waiting)
    return 'Waiting for refund';
  return switch (item.state) {
    ItemState.draft => 'Needs decision',
    ItemState.waiting =>
      item.waitingOn.isNotEmpty
          ? 'Waiting for ${_cleanWaitingTarget(item.waitingOn)}'
          : 'Waiting for update',
    ItemState.missingInfo => 'Needs information',
    ItemState.overdue => 'Overdue',
    ItemState.dueSoon => 'Not due yet',
    ItemState.open =>
      item.dueText.isMeaningfulFollowUpDate ||
              item.reminderText.isMeaningfulFollowUpDate
          ? 'Not due yet'
          : 'Needs follow-up',
    ItemState.done || ItemState.ignored => 'Done',
  };
}

String minimalFollowUpLine(StillOpenItem item) {
  final due = displayStillOpenDate(item.dueText, item.dueAt);
  final reminder = displayStillOpenDate(item.reminderText, item.reminderAt);
  final followUp = displayStillOpenDate(item.followUpText, item.followUpAt);
  final dateLine = due.isMeaningfulFollowUpDate
      ? 'Due ${due.stripDatePrefix('due')}'
      : reminder.isMeaningfulFollowUpDate
      ? 'Reminder ${reminder.stripDatePrefix('reminder')}'
      : followUp.isMeaningfulFollowUpDate
      ? 'Follow up ${followUp.stripDatePrefix('follow-up').stripDatePrefix('follow up')}'
      : 'No follow-up set';
  final waiting = item.waitingSinceAt != null
      ? 'Waiting since ${formatWaitingSince(item.waitingSinceAt!)}'
      : item.waitingSinceText.trim().toLowerCase() == 'just now'
      ? 'Waiting start not recorded'
      : item.waitingSinceText.trim().isEmpty
      ? null
      : item.waitingSinceText.startsWith(
          RegExp('waiting since', caseSensitive: false),
        )
      ? _capitalize(item.waitingSinceText)
      : 'Waiting since ${item.waitingSinceText}';
  return [dateLine, waiting].whereType<String>().join(' · ');
}

String minimalNextActionLabel(StillOpenItem item) {
  if ({ItemState.done, ItemState.ignored}.contains(item.state))
    return 'Reopen if this needs attention again';
  if (isMedicalWorkflowItem(item)) return _medicalPrimaryActionLabel(item);
  if (item.templateType == TemplateType.longTerm) {
    return item.state == ItemState.waiting || item.waitingOn.isNotEmpty
        ? 'Change reminder'
        : 'Mark booked';
  }
  return switch (item.state) {
    ItemState.draft => 'Move to Open',
    ItemState.waiting => 'Add update',
    _ =>
      item.reminderText.isEmpty && item.followUpText.isEmpty
          ? 'Set reminder'
          : 'Change reminder',
  };
}

String controlSummaryBody(ItemWithDetails details) {
  final item = details.item;
  if (isMedicalWorkflowItem(item) && item.claimStage.isNotEmpty) {
    final waiting = item.waitingOn.isNotEmpty
        ? 'Waiting for ${_cleanWaitingTarget(item.waitingOn)}.'
        : 'Choose the next step.';
    return '${minimalStatusSentence(item)}. $waiting';
  }
  if (item.templateType == TemplateType.longTerm) {
    return item.nextCycleAt.isNotEmpty
        ? 'Next reminder: ${item.nextCycleAt}.'
        : 'Responsibility remembered. Appointment not booked yet.';
  }
  if (item.state == ItemState.waiting) {
    return 'Waiting for follow-up${item.followUpText.isEmpty ? '.' : ' on ${item.followUpText}.'}';
  }
  if (item.dueText.isNotEmpty && item.reminderText.isNotEmpty)
    return 'Due ${item.dueText.toLowerCase()}. Reminder set.';
  if (item.dueText.isNotEmpty)
    return 'Due ${item.dueText.toLowerCase()}. No reminder set.';
  if (item.reminderText.isNotEmpty)
    return 'Reminder set for ${item.reminderText}.';
  return 'Saved, but no reminder is set.';
}

List<String> stillOpenFacts(ItemWithDetails details) {
  final item = details.item;
  if (isMedicalWorkflowItem(item)) {
    return [
      switch (sourceTrustState(details)) {
        SourceTrustState.localFileAvailable => 'Invoice saved',
        SourceTrustState.sampleSource => 'Sample source',
        SourceTrustState.labelOnly => 'No file saved',
        SourceTrustState.missingOrBroken => 'Source unavailable',
        SourceTrustState.noSource => 'Needs source',
      },
      if (item.claimStage.isNotEmpty) item.claimStage,
      if (item.waitingOn.isNotEmpty)
        'Waiting for ${_cleanWaitingTarget(item.waitingOn)}',
      if (item.isSharedCopy) 'Shared copy',
    ];
  }
  if (item.templateType == TemplateType.longTerm) {
    return [
      item.nextCycleAt.isNotEmpty
          ? 'Reminder set for ${item.nextCycleAt}'
          : 'No next reminder',
      if (item.recurrenceHint.isNotEmpty) item.recurrenceHint,
      item.state == ItemState.waiting
          ? 'Waiting'
          : 'Appointment not booked yet',
    ];
  }
  return [
    sourceTrustLabel(details),
    if (item.reminderText.isNotEmpty)
      'Reminder set'
    else if (item.dueText.isNotEmpty && item.dueText != 'No date')
      'Due ${item.dueText}'
    else
      'Needs date',
    if (item.followUpText.isNotEmpty) 'Follow-up ${item.followUpText}',
    if (item.state == ItemState.waiting) 'Waiting',
    if (item.ocrText.isNotEmpty) 'Text found',
    if (item.isSharedCopy) 'Shared copy',
  ];
}

String dateFieldLabel(StillOpenItem item) =>
    item.state == ItemState.waiting ? 'Follow-up' : 'Due date';

enum SourceTrustState {
  localFileAvailable,
  sampleSource,
  labelOnly,
  missingOrBroken,
  noSource,
}

SourceTrustState sourceTrustState(ItemWithDetails details) {
  final item = details.item;
  final attachments = details.attachments
      .where((attachment) => attachment.uri.isNotEmpty)
      .toList();
  if (attachments.any((attachment) => _localAttachmentReadable(attachment.uri)))
    return SourceTrustState.localFileAvailable;
  if (attachments.isNotEmpty) return SourceTrustState.missingOrBroken;
  if (item.sourceType == SourceType.sample)
    return SourceTrustState.sampleSource;
  if (item.sourceLabel.toLowerCase().contains('could not') ||
      item.sourceLabel.toLowerCase().contains('unavailable') ||
      item.sourceLabel.toLowerCase().contains('needs attention')) {
    return SourceTrustState.missingOrBroken;
  }
  if (item.sourceLabel.isNotEmpty || item.sourceType == SourceType.sharedText)
    return SourceTrustState.labelOnly;
  if ({
    SourceType.camera,
    SourceType.image,
    SourceType.sharedImage,
    SourceType.pdf,
  }.contains(item.sourceType))
    return SourceTrustState.missingOrBroken;
  return SourceTrustState.noSource;
}

bool durableSourceSaved(ItemWithDetails details) =>
    sourceTrustState(details) == SourceTrustState.localFileAvailable;

bool sampleSource(ItemWithDetails details) =>
    details.item.sourceType == SourceType.sample;

bool sourceAvailable(ItemWithDetails details) =>
    sourceTrustState(details) != SourceTrustState.noSource;

String sourceShortLabel(ItemWithDetails details) {
  final item = details.item;
  return switch (sourceTrustState(details)) {
    SourceTrustState.localFileAvailable =>
      details.attachments
          .firstWhere((attachment) => _localAttachmentReadable(attachment.uri))
          .label
          .ifBlank('Source saved locally'),
    SourceTrustState.sampleSource => item.sourceLabel.ifBlank('Sample source'),
    SourceTrustState.labelOnly => item.sourceLabel.ifBlank(
      item.sourceType == SourceType.sharedText
          ? 'Shared text'
          : 'No file saved',
    ),
    SourceTrustState.missingOrBroken => 'Source unavailable',
    SourceTrustState.noSource => 'None',
  };
}

String sourceTitle(ItemWithDetails details) {
  final item = details.item;
  return switch (sourceTrustState(details)) {
    SourceTrustState.localFileAvailable => 'Source saved locally',
    SourceTrustState.sampleSource => 'Sample source',
    SourceTrustState.labelOnly =>
      item.sourceLabelConfidence == SourceLabelConfidence.inferred &&
              item.sourceLabel.isNotEmpty
          ? 'Looks like ${item.sourceLabel}'
          : item.sourceLabel.isNotEmpty
          ? 'Source label: ${item.sourceLabel} · no file saved'
          : item.sourceType == SourceType.sharedText
          ? 'Shared text'
          : 'No file saved',
    SourceTrustState.missingOrBroken => 'Source unavailable',
    SourceTrustState.noSource => 'No source saved',
  };
}

String sourceTrustLabel(ItemWithDetails details) =>
    switch (sourceTrustState(details)) {
      SourceTrustState.localFileAvailable => 'Source saved locally',
      SourceTrustState.sampleSource => 'Sample source',
      SourceTrustState.labelOnly => 'No file saved',
      SourceTrustState.missingOrBroken => 'Source unavailable',
      SourceTrustState.noSource => 'No source saved',
    };

String sourceTypeLabel(ItemWithDetails details) {
  final sourceType =
      details.attachments.firstOrNull?.sourceType ?? details.item.sourceType;
  return switch (sourceType) {
    SourceType.camera => 'Camera photo',
    SourceType.image => 'Image',
    SourceType.sharedImage => 'Shared image',
    SourceType.sharedText => 'Shared text',
    SourceType.pdf => 'PDF',
    SourceType.manual => 'Manual note',
    SourceType.sample => 'Sample source',
  };
}

String sourceDescription(ItemWithDetails details) {
  final item = details.item;
  return switch (sourceTrustState(details)) {
    SourceTrustState.localFileAvailable =>
      'Source saved locally · ${details.attachments.firstWhere((attachment) => _localAttachmentReadable(attachment.uri)).sourceType.name.pascalName}',
    SourceTrustState.sampleSource =>
      'Sample source preview. No real file is attached.',
    SourceTrustState.labelOnly =>
      item.sourceType == SourceType.sharedText || item.notes.isNotEmpty
          ? item.notes.take(120).ifBlank('Shared text source. No file saved.')
          : item.sourceLabel.isNotEmpty
          ? 'Source label: ${item.sourceLabel} · no file saved'
          : 'No file saved',
    SourceTrustState.missingOrBroken => 'The saved source could not be opened.',
    SourceTrustState.noSource => 'No source saved.',
  };
}

String minimalSourceStatus(ItemWithDetails details) {
  final item = details.item;
  return switch (sourceTrustState(details)) {
    SourceTrustState.localFileAvailable => _savedSourceStatus(details),
    SourceTrustState.sampleSource => item.sourceLabel.ifBlank('Sample source'),
    SourceTrustState.labelOnly =>
      item.sourceType == SourceType.sharedText && item.notes.isNotEmpty
          ? 'Shared text saved'
          : 'No file saved',
    SourceTrustState.missingOrBroken => 'Source unavailable',
    SourceTrustState.noSource => 'No source saved',
  };
}

bool minimalSourceCanOpen(ItemWithDetails details) {
  return {
        SourceTrustState.localFileAvailable,
        SourceTrustState.sampleSource,
      }.contains(sourceTrustState(details)) ||
      (details.item.sourceType == SourceType.sharedText &&
          details.item.notes.isNotEmpty);
}

bool followUpOverdue(StillOpenItem item) {
  final when = item.followUpAt == null
      ? parseStillOpenDate(
          item.followUpText,
          anchor: item.updatedAt > 0
              ? DateTime.fromMillisecondsSinceEpoch(item.updatedAt)
              : null,
        )
      : DateTime.fromMillisecondsSinceEpoch(item.followUpAt!);
  if (when != null && when.isBefore(clock.now())) return true;
  final text = item.followUpText.toLowerCase();
  return [
    'overdue',
    'yesterday',
    'past',
    'last week',
    'last month',
  ].any(text.contains);
}

bool waitingNeedsFollowUp(StillOpenItem item) =>
    item.state == ItemState.waiting &&
    (item.followUpText.isEmpty ||
        item.followUpText.toLowerCase() == 'pick date');

bool waitingTooLong(StillOpenItem item) {
  if (item.state != ItemState.waiting) return false;
  final threshold =
      {
        Category.medical,
        Category.shopping,
        Category.money,
        Category.school,
      }.contains(item.category)
      ? 14
      : 30;
  if (item.waitingSinceAt != null) {
    return clock
            .now()
            .difference(
              DateTime.fromMillisecondsSinceEpoch(item.waitingSinceAt!),
            )
            .inDays >
        threshold;
  }
  final waitingText = item.waitingSinceText.toLowerCase();
  final explicitDays = RegExp(
    r'(\d+)\s*days?',
  ).firstMatch(waitingText)?.group(1);
  if (explicitDays != null) return int.parse(explicitDays) > threshold;
  return waitingText.contains('month') || waitingText.contains('long');
}

String formatWaitingSince(int epoch) {
  final date = DateTime.fromMillisecondsSinceEpoch(epoch);
  return '${_monthName(date.month)} ${date.day}, ${date.year}';
}

bool draftNeedsDecision(StillOpenItem item) =>
    item.state == ItemState.draft &&
    clock.now().millisecondsSinceEpoch - item.createdAt >
        7 * 24 * 60 * 60 * 1000;

String nextSentence(StillOpenItem item) => switch (item.state) {
  ItemState.draft => 'Draft. Not visible in Open yet.',
  ItemState.waiting =>
    'Still open because: waiting for ${item.followUpText.ifBlank('follow-up')}.',
  ItemState.dueSoon =>
    'Still open because: due ${item.dueText.ifBlank(item.reminderText.ifBlank('soon'))}.',
  ItemState.done || ItemState.ignored =>
    item.sourceLabel.isNotEmpty || item.sourceType != SourceType.manual
        ? 'Done. Findable in Done. Original source kept.'
        : 'Done. Findable in Done.',
  ItemState.overdue => 'Still open because: overdue.',
  ItemState.missingInfo => 'Still open because: missing information.',
  ItemState.open => 'Still open until Done.',
};

extension StringPresentation on String {
  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;

  String take(int maxLength) =>
      length <= maxLength ? this : substring(0, maxLength);

  bool get isMeaningfulFollowUpDate {
    final clean = trim();
    return clean.isNotEmpty &&
        ![
          'no date',
          'pick date',
          'pick a date',
          'none',
        ].contains(clean.toLowerCase());
  }

  String stripDatePrefix(String prefix) {
    final clean = trim();
    if (!clean.toLowerCase().startsWith(prefix.toLowerCase())) return clean;
    return clean.substring(prefix.length).replaceFirst(RegExp(r'^[: ·]+'), '');
  }

  String get pascalName =>
      isEmpty ? this : this[0].toUpperCase() + substring(1);
}

int? _dateRankFromLabel(String label, {DateTime? today, StillOpenItem? item}) {
  final value = label.trim();
  if (value.isEmpty || value.toLowerCase() == 'no date') return null;
  final base = today ?? clock.now();
  final parsed = parseStillOpenDate(value, anchor: base);
  if (parsed != null) return _dayRank(parsed);
  if (value.toLowerCase().startsWith('today')) return _dayRank(base);
  if (value.toLowerCase().startsWith('tomorrow'))
    return _dayRank(calendarDayAfter(base, 1));
  if (value.toLowerCase().startsWith('this weekend'))
    return _dayRank(_nextOrSame(base, DateTime.saturday));
  final weekday = _weekdayFor(value);
  if (weekday != null) return _dayRank(_nextOrSame(base, weekday));
  final monthDate = _monthDateFor(value, base.year);
  return monthDate == null ? null : _dayRank(monthDate);
}

DateTime _nextOrSame(DateTime today, int weekday) {
  final delta = weekday - today.weekday >= 0
      ? weekday - today.weekday
      : weekday - today.weekday + 7;
  return calendarDayAfter(today, delta);
}

int? _weekdayFor(String label) {
  final key = label.split(' ').first.toLowerCase();
  return switch (key) {
    'monday' => DateTime.monday,
    'tuesday' => DateTime.tuesday,
    'wednesday' => DateTime.wednesday,
    'thursday' => DateTime.thursday,
    'friday' => DateTime.friday,
    'saturday' => DateTime.saturday,
    'sunday' => DateTime.sunday,
    _ => null,
  };
}

DateTime? _monthDateFor(String label, int year) {
  final match = RegExp(r'^([A-Za-z]+)\s+(\d{1,2})').firstMatch(label);
  if (match == null) return null;
  final month = switch (match.group(1)!.toLowerCase()) {
    'jan' || 'january' => 1,
    'feb' || 'february' => 2,
    'mar' || 'march' => 3,
    'apr' || 'april' => 4,
    'may' => 5,
    'jun' || 'june' => 6,
    'jul' || 'july' => 7,
    'aug' || 'august' => 8,
    'sep' || 'sept' || 'september' => 9,
    'oct' || 'october' => 10,
    'nov' || 'november' => 11,
    'dec' || 'december' => 12,
    _ => null,
  };
  if (month == null) return null;
  final day = int.parse(match.group(2)!);
  if (day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  return date.month == month && date.day == day ? date : null;
}

int _dayRank(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

String _monthName(int month) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];

String _cleanWaitingTarget(String value) {
  final clean = value.trim().replaceFirst(
    RegExp(r'^(for|on)\s+', caseSensitive: false),
    '',
  );
  return clean.isEmpty ? clean : clean[0].toLowerCase() + clean.substring(1);
}

String _medicalPrimaryActionLabel(StillOpenItem item) {
  final stage = item.claimStage.toLowerCase();
  if (item.claimStage.toLowerCase().startsWith('extra step:'))
    return 'Step done';
  if (stage.contains('waiting for appointment')) return 'Have the appointment';
  if (stage.contains('appointment done')) return 'Mark submitted';
  if (stage.contains('private response')) return 'Mark reimbursed';
  if (stage.contains('response received'))
    return 'Forward to private insurance';
  if (stage.contains('forwarded')) return 'Add private response';
  if (stage.contains('reimbursed')) return 'Mark Done';
  if (stage.contains('submitted') ||
      stage.contains('waiting') ||
      item.state == ItemState.waiting)
    return 'Add insurance response';
  return 'Book appointment';
}

String _savedSourceStatus(ItemWithDetails details) {
  final readable = details.attachments
      .where((attachment) => _localAttachmentReadable(attachment.uri))
      .toList();
  if (readable.length > 1) return '${readable.length} attachments saved';
  final attachment = readable.firstOrNull;
  final label = attachment?.label.trim() ?? '';
  if (label.isNotEmpty && label.toLowerCase() != 'source saved')
    return '${label.replaceFirst(RegExp(r' saved$', caseSensitive: false), '')} saved';
  final item = details.item;
  final sourceType = attachment?.sourceType ?? item.sourceType;
  if (sourceType == SourceType.pdf) return 'PDF saved';
  if (isMedicalWorkflowItem(item)) return 'Invoice photo saved';
  if ({
    TemplateType.shoppingReturn,
    TemplateType.document,
  }.contains(item.templateType))
    return 'Proof saved';
  return 'Source saved';
}

bool _localAttachmentReadable(String uri) {
  try {
    final path = uri.startsWith('file:')
        ? Uri.parse(uri).toFilePath()
        : uri.startsWith('/')
        ? uri
        : null;
    if (path == null) return false;
    final type = FileSystemEntity.typeSync(path);
    return type == FileSystemEntityType.file;
  } on Object {
    return false;
  }
}

String _capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

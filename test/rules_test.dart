import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/models.dart';
import 'package:stillopen/src/rules.dart';
import 'package:stillopen/src/step_templates.dart';

void main() {
  test('suggests Android source-of-truth categories from titles', () {
    expect(
      StillOpenRules.suggestCategoryFromTitle('School trip permission form'),
      Category.school,
    );
    expect(
      StillOpenRules.suggestCategoryFromTitle(
        'Physiotherapy insurance claim reimbursement',
      ),
      Category.medical,
    );
    expect(
      StillOpenRules.suggestCategoryFromTitle(
        'Annual certificate renewal next cycle',
      ),
      Category.longTerm,
    );
    expect(
      StillOpenRules.suggestCategoryFromTitle('Refund return order'),
      Category.shopping,
    );
    expect(
      StillOpenRules.suggestCategoryFromTitle('Subscription invoice payment'),
      Category.money,
    );
    expect(
      StillOpenRules.suggestCategoryFromTitle('Warranty repair appliance'),
      Category.home,
    );
    expect(
      StillOpenRules.suggestCategoryFromTitle(
        'PDF document proof certificate copy',
      ),
      Category.documents,
    );
    expect(
      StillOpenRules.suggestCategoryFromTitle('Office client meeting at work'),
      Category.work,
    );
    expect(
      StillOpenRules.suggestCategoryFromTitle('Doctor appointment for kids'),
      Category.family,
    );
    expect(
      StillOpenRules.suggestCategoryFromTitle(
        'Personal passport license health',
      ),
      Category.personal,
    );
    expect(
      StillOpenRules.suggestCategoryFromTitle('Plain captured note'),
      isNull,
    );
  });

  test('lifecycle rules match Android forward backward and tab mapping', () {
    expect(StillOpenRules.forwardState(ItemState.draft), ItemState.open);
    for (final state in [
      ItemState.open,
      ItemState.dueSoon,
      ItemState.waiting,
      ItemState.missingInfo,
      ItemState.overdue,
      ItemState.done,
      ItemState.ignored,
    ]) {
      expect(StillOpenRules.forwardState(state), ItemState.done);
    }
    for (final state in [
      ItemState.open,
      ItemState.dueSoon,
      ItemState.waiting,
      ItemState.missingInfo,
      ItemState.overdue,
    ]) {
      expect(StillOpenRules.backwardState(state), ItemState.draft);
      expect(StillOpenRules.tabForState(state), HomeTab.open);
    }
    expect(StillOpenRules.backwardState(ItemState.done), ItemState.open);
    expect(StillOpenRules.tabForState(ItemState.draft), HomeTab.draft);
    expect(StillOpenRules.tabForState(ItemState.done), HomeTab.done);
  });

  test('filters searches and sorts items like Android rules', () {
    final items = [
      item(id: 1, title: 'No date', category: Category.work, updatedAt: 20),
      item(
        id: 2,
        title: 'Tomorrow with today reminder',
        category: Category.school,
        updatedAt: 10,
        dueText: 'Tomorrow',
        reminderText: 'Today 09:00',
      ),
      item(
        id: 3,
        title: 'Today',
        category: Category.home,
        updatedAt: 30,
        dueText: 'Today',
      ),
      item(
        id: 4,
        title: 'Done proof',
        state: ItemState.done,
        category: Category.shopping,
        closedText: 'Done with proof',
      ),
      item(
        id: 5,
        title: 'Draft sports',
        state: ItemState.draft,
        category: Category.school,
        notes: 'Bring sports shoes',
      ),
    ];

    expect(filterForTab(items, HomeTab.open).map((item) => item.id), [1, 2, 3]);
    expect(filterForTab(items, HomeTab.draft).map((item) => item.id), [5]);
    expect(filterForTab(items, HomeTab.done).map((item) => item.id), [4]);
    expect(filterSearch(items, 'sports').map((item) => item.id), [5]);
    expect(filterSearch(items, 'proof').map((item) => item.id), [4]);
    expect(
      sortForMode(
        items.take(3).toList(),
        SortMode.smart,
        today: DateTime(2026, 5, 27),
      ).map((item) => item.id).take(2),
      [3, 2],
    );
    expect(
      sortForMode(
        items.take(3).toList(),
        SortMode.updated,
      ).map((item) => item.id),
      [3, 1, 2],
    );
  });

  test(
    'presentation copy covers medical long-term source and waiting states',
    () {
      final medical = item(
        state: ItemState.waiting,
        category: Category.medical,
        templateType: TemplateType.medicalClaim,
        claimStage: 'Waiting for insurance response',
        waitingOn: 'Insurance',
        dueText: 'May 24',
        waitingSinceText: 'today',
      );
      expect(minimalCategoryLabel(medical), 'Medical claim');
      expect(minimalStatusSentence(medical), 'Waiting for insurance response');
      expect(minimalFollowUpLine(medical), 'Due May 24 · Waiting since today');
      expect(minimalNextActionLabel(medical), 'Add insurance response');
      expect(
        controlSummaryBody(ItemWithDetails(item: medical)),
        'Waiting for insurance response. Waiting for insurance.',
      );
      final categoryOnlyMedical = item(
        title: 'Doctor invoice reimbursement',
        category: Category.medical,
      );
      expect(isMedicalWorkflowItem(categoryOnlyMedical), isTrue);
      expect(minimalStatusSentence(categoryOnlyMedical), 'Needs submission');
      expect(minimalNextActionLabel(categoryOnlyMedical), 'Book appointment');

      final longTerm = item(
        category: Category.longTerm,
        templateType: TemplateType.longTerm,
        nextCycleAt: 'November',
      );
      expect(stillOpenFacts(ItemWithDetails(item: longTerm)), [
        'Reminder set for November',
        'Appointment not booked yet',
      ]);
      expect(minimalNextActionLabel(longTerm), 'Mark booked');
    },
  );

  test(
    'source trust stays honest for local, sample, label-only, and broken sources',
    () {
      final dir = Directory.systemTemp.createTempSync('stillopen-source');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/source.jpg')..writeAsStringSync('fake');
      addTearDown(file.deleteSync);
      final local = ItemWithDetails(
        item: item(sourceType: SourceType.camera, sourceLabel: 'Source saved'),
        attachments: [
          ItemAttachment(
            itemId: 1,
            uri: file.uri.toString(),
            label: 'Source saved',
            sourceType: SourceType.camera,
          ),
        ],
      );
      expect(durableSourceSaved(local), isTrue);
      expect(minimalSourceStatus(local), 'Source saved');
      expect(sourceTypeLabel(local), 'Camera photo');

      expect(
        sourceTrustState(
          ItemWithDetails(item: item(sourceType: SourceType.sample)),
        ),
        SourceTrustState.sampleSource,
      );
      expect(
        sourceTrustState(
          ItemWithDetails(
            item: item(
              sourceType: SourceType.sharedImage,
              sourceLabel: 'WebUntis',
            ),
          ),
        ),
        SourceTrustState.labelOnly,
      );
      expect(
        sourceTrustState(
          ItemWithDetails(
            item: item(sourceType: SourceType.image),
            attachments: const [
              ItemAttachment(
                itemId: 1,
                uri: '/tmp/missing.jpg',
                label: 'Camera',
                sourceType: SourceType.image,
              ),
            ],
          ),
        ),
        SourceTrustState.missingOrBroken,
      );
    },
  );

  test('default steps preserve product workflow shape', () {
    expect(
      DefaultStepTemplates.forCategory(
        Category.medical,
      ).map((step) => step.title),
      [
        'Invoice saved',
        'Submit to insurance',
        'Wait for response',
        'Submit to private insurance',
        'Wait for private response',
        'Mark reimbursed or Done',
      ],
    );
    expect(
      DefaultStepTemplates.all().map((step) => step.category).toSet(),
      Category.values.toSet(),
    );
  });

  test('status labels row metadata and next sentences cover state matrix', () {
    final oldDraft = item(
      state: ItemState.draft,
      createdAt: DateTime.now()
          .subtract(const Duration(days: 10))
          .millisecondsSinceEpoch,
    );
    expect(statusLabel(oldDraft), 'Needs decision');
    expect(nextSentence(oldDraft), 'Draft. Not visible in Open yet.');

    expect(statusLabel(item(state: ItemState.draft)), 'Draft');
    expect(statusLabel(item(state: ItemState.done)), 'Findable');
    expect(
      statusLabel(
        item(
          state: ItemState.waiting,
          followUpText: 'overdue yesterday',
          category: Category.medical,
        ),
      ),
      'Follow-up overdue',
    );
    expect(
      statusLabel(
        item(
          state: ItemState.waiting,
          waitingSinceText: '31 days',
          category: Category.home,
        ),
      ),
      'Waiting too long',
    );
    expect(
      statusLabel(item(state: ItemState.waiting, followUpText: 'Pick date')),
      'Needs follow-up',
    );
    expect(statusLabel(item(state: ItemState.missingInfo)), 'Missing info');
    expect(statusLabel(item(state: ItemState.overdue)), 'Overdue');
    expect(statusLabel(item(reminderText: 'Tomorrow')), 'Reminder set');
    expect(statusLabel(item(sourceType: SourceType.sample)), 'Sample source');
    expect(
      statusLabel(item(sourceType: SourceType.camera)),
      'Source needs check',
    );
    expect(statusLabel(item(sourceLabel: 'Email')), 'Source label');
    expect(statusLabel(item(dueText: 'Friday')), 'Needs reminder');
    expect(statusLabel(item()), 'Needs date');

    final templates = {
      TemplateType.medicalClaim: 'Medical',
      TemplateType.schoolHomework: 'School · homework',
      TemplateType.school: 'School',
      TemplateType.longTerm: 'Long-term',
      TemplateType.shoppingReturn: 'Shopping',
      TemplateType.home: 'Home',
      TemplateType.money: 'Money',
      TemplateType.document: 'Documents',
      TemplateType.quickNote: 'Home · assigned to Me',
      TemplateType.other: 'Home · loose end',
    };
    for (final entry in templates.entries) {
      expect(
        rowMetaHint(
          item(
            templateType: entry.key,
            assignedTo: entry.key == TemplateType.quickNote ? 'Me' : '',
          ),
        ),
        startsWith(entry.value),
      );
    }

    expect(
      nextSentence(item(state: ItemState.waiting, followUpText: 'school')),
      'Still open because: waiting for school.',
    );
    expect(
      nextSentence(item(state: ItemState.dueSoon, dueText: 'Tomorrow')),
      'Still open because: due Tomorrow.',
    );
    expect(
      nextSentence(
        item(
          state: ItemState.done,
          sourceType: SourceType.pdf,
          sourceLabel: 'PDF',
        ),
      ),
      'Done. Findable in Done. Original source kept.',
    );
    expect(
      nextSentence(item(state: ItemState.overdue)),
      'Still open because: overdue.',
    );
    expect(
      nextSentence(item(state: ItemState.missingInfo)),
      'Still open because: missing information.',
    );
    expect(nextSentence(item(state: ItemState.open)), 'Still open until Done.');
  });

  test('minimal labels and source descriptions cover branch matrix', () {
    final stages = {
      'Private response received': 'Ready to close',
      'Response received': 'Response received',
      'Forwarded to private': 'Waiting for private insurance response',
      'Submitted': 'Waiting for insurance response',
      '': 'Needs submission',
    };
    for (final entry in stages.entries) {
      expect(
        minimalStatusSentence(
          item(
            templateType: TemplateType.medicalClaim,
            category: Category.medical,
            claimStage: entry.key,
          ),
        ),
        entry.value,
      );
    }
    expect(
      minimalStatusSentence(
        item(
          templateType: TemplateType.shoppingReturn,
          state: ItemState.waiting,
        ),
      ),
      'Waiting for refund',
    );
    expect(
      minimalStatusSentence(item(state: ItemState.draft)),
      'Needs decision',
    );
    expect(
      minimalStatusSentence(
        item(state: ItemState.waiting, waitingOn: 'for Parent'),
      ),
      'Waiting for parent',
    );
    expect(
      minimalStatusSentence(item(state: ItemState.missingInfo)),
      'Needs information',
    );
    expect(minimalStatusSentence(item(state: ItemState.overdue)), 'Overdue');
    expect(
      minimalStatusSentence(item(state: ItemState.dueSoon)),
      'Not due yet',
    );
    expect(minimalStatusSentence(item(dueText: 'Tomorrow')), 'Not due yet');
    expect(minimalStatusSentence(item()), 'Needs follow-up');

    expect(minimalFollowUpLine(item()), 'No follow-up set');
    expect(
      minimalFollowUpLine(item(reminderText: 'Reminder Tomorrow')),
      'Reminder Tomorrow',
    );
    expect(
      minimalFollowUpLine(item(followUpText: 'Follow up Friday')),
      'Follow up Friday',
    );
    expect(
      minimalFollowUpLine(
        item(dueText: 'Due Monday', waitingSinceText: 'last week'),
      ),
      'Due Monday · Waiting since last week',
    );
    expect(dateFieldLabel(item(state: ItemState.waiting)), 'Follow-up');
    expect(dateFieldLabel(item()), 'Due date');

    final labelOnly = ItemWithDetails(
      item: item(sourceType: SourceType.sharedText, notes: 'shared body'),
    );
    expect(sourceShortLabel(labelOnly), 'Shared text');
    expect(sourceTitle(labelOnly), 'Shared text');
    expect(sourceDescription(labelOnly), 'shared body');
    expect(minimalSourceStatus(labelOnly), 'Shared text saved');
    expect(minimalSourceCanOpen(labelOnly), isTrue);

    final inferred = ItemWithDetails(
      item: item(
        sourceLabel: 'WebUntis',
        sourceLabelConfidence: SourceLabelConfidence.inferred,
      ),
    );
    expect(sourceTitle(inferred), 'Looks like WebUntis');
    expect(
      sourceDescription(inferred),
      'Source label: WebUntis · no file saved',
    );

    final broken = ItemWithDetails(
      item: item(sourceLabel: 'Source unavailable'),
    );
    expect(sourceTrustState(broken), SourceTrustState.missingOrBroken);
    expect(sourceDescription(broken), 'The saved source could not be opened.');
    expect(minimalSourceCanOpen(broken), isFalse);

    final noSource = ItemWithDetails(item: item());
    expect(sourceShortLabel(noSource), 'None');
    expect(sourceTitle(noSource), 'No source saved');
    expect(sourceDescription(noSource), 'No source saved.');
    expect(sourceTypeLabel(noSource), 'Manual note');
  });

  test('date ranking parses relative weekdays months and invalid labels', () {
    final base = DateTime(2026, 5, 28); // Thursday
    expect(
      sortDateRank(item(dueText: 'Today 09:00'), today: base),
      lessThan(sortDateRank(item(dueText: 'Tomorrow'), today: base)),
    );
    expect(
      sortDateRank(item(dueText: 'This weekend'), today: base),
      sortDateRank(item(dueText: 'Saturday'), today: base),
    );
    expect(
      sortDateRank(item(dueText: 'Friday'), today: base),
      lessThan(sortDateRank(item(dueText: 'Sunday'), today: base)),
    );
    expect(
      sortDateRank(item(dueText: 'Jun 4'), today: base),
      isNot(0x7fffffff),
    );
    expect(sortDateRank(item(dueText: 'February 31'), today: base), 0x7fffffff);
    expect(
      StillOpenRules.dateLabelFromDate(DateTime(2026, 12, 5)),
      'December 5',
    );
    expect('Reminder: Tomorrow'.stripDatePrefix('reminder'), 'Tomorrow');
    expect('abc'.take(2), 'ab');
    expect('abc'.pascalName, 'Abc');
  });
}

StillOpenItem item({
  int id = 1,
  String title = 'Item',
  String notes = '',
  ItemState state = ItemState.open,
  Category category = Category.home,
  TemplateType templateType = TemplateType.quickNote,
  Priority priority = Priority.normal,
  SourceType sourceType = SourceType.manual,
  String sourceLabel = '',
  SourceLabelConfidence sourceLabelConfidence = SourceLabelConfidence.unknown,
  String dueText = '',
  String reminderText = '',
  String followUpText = '',
  String closedText = '',
  String waitingSinceText = '',
  String waitingOn = '',
  String assignedTo = '',
  String claimStage = '',
  String nextCycleAt = '',
  bool privateInsuranceSkipped = false,
  ClosureReason closureReason = ClosureReason.none,
  int? createdAt,
  int updatedAt = 0,
}) {
  return StillOpenItem(
    id: id,
    title: title,
    notes: notes,
    state: state,
    category: category,
    templateType: templateType,
    priority: priority,
    sourceType: sourceType,
    sourceLabel: sourceLabel,
    sourceLabelConfidence: sourceLabelConfidence,
    dueText: dueText,
    reminderText: reminderText,
    followUpText: followUpText,
    closedText: closedText,
    waitingSinceText: waitingSinceText,
    waitingOn: waitingOn,
    assignedTo: assignedTo,
    claimStage: claimStage,
    nextCycleAt: nextCycleAt,
    privateInsuranceSkipped: privateInsuranceSkipped,
    closureReason: closureReason,
    createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
    updatedAt: updatedAt,
  );
}

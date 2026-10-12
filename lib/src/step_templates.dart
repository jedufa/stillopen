import 'models.dart';

class DefaultStepTemplates {
  const DefaultStepTemplates._();

  static List<CategoryStepTemplate> all() =>
      Category.values.expand(forCategory).toList(growable: false);

  static List<CategoryStepTemplate> forCategory(Category category) {
    final labels = switch (category) {
      Category.medical => [
        'Invoice saved',
        'Submit to insurance',
        'Wait for response',
        'Submit to private insurance',
        'Wait for private response',
        'Mark reimbursed or Done',
      ],
      Category.school => [
        'Capture school request',
        'Check date and child',
        'Prepare response',
        'Send or pack it',
        'Mark complete',
      ],
      Category.longTerm => [
        'Define recurrence',
        'Set next reminder',
        'Book or handle it',
        'Set next cycle',
      ],
      Category.shopping => [
        'Save proof',
        'Return or contact merchant',
        'Wait for refund',
        'Confirm money arrived',
      ],
      Category.money => [
        'Save bill',
        'Check amount and date',
        'Pay or dispute',
        'Confirm closed',
      ],
      Category.documents => [
        'Save document',
        'Make it findable',
        'Use or file it',
        'Confirm no action remains',
      ],
      Category.home => [
        'Save proof',
        'Contact provider',
        'Wait for response',
        'Confirm fixed',
      ],
      _ => [
        'Capture what matters',
        'Decide next action',
        'Follow up',
        'Mark Done',
      ],
    };
    return [
      for (final entry in labels.indexed)
        CategoryStepTemplate(
          id: '${category.name}_${entry.$1}',
          category: category,
          title: entry.$2,
          type: entry.$1 == labels.length - 1
              ? StepType.finalStep
              : StepType.action,
          appliesMode: AppliesMode.always,
          sortOrder: entry.$1,
        ),
    ];
  }
}

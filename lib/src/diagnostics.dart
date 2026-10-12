import 'package:clock/clock.dart';

import 'package:flutter/foundation.dart';

class StillOpenDiagnostics {
  StillOpenDiagnostics._();

  static final StillOpenDiagnostics instance = StillOpenDiagnostics._();

  static const _maxEvents = 20;
  static const _maxMessageChars = 500;
  static const _maxStackChars = 2000;

  final List<Map<String, Object?>> _events = [];

  void recordFlutterError(FlutterErrorDetails details) {
    recordError(
      source: 'flutter',
      message: details.exceptionAsString(),
      stack: details.stack?.toString(),
    );
  }

  bool recordPlatformError(Object error, StackTrace stack) {
    recordError(
      source: 'platform',
      message: error.toString(),
      stack: stack.toString(),
    );
    return true;
  }

  void recordError({
    required String source,
    required String message,
    String? stack,
  }) {
    final safeMessage = source.startsWith('incoming_share')
        ? 'Incoming share handling failed.'
        : message;
    _events.add({
      'captured_at': clock.now().toUtc().toIso8601String(),
      'source': source,
      'message': redactText(safeMessage, maxChars: _maxMessageChars),
      if (stack != null) 'stack': redactText(_take(stack, _maxStackChars)),
    });
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
  }

  Map<String, Object?> toJson() => {
    'captured_at': clock.now().toUtc().toIso8601String(),
    'recent_errors': List.unmodifiable(_events),
  };

  @visibleForTesting
  void clearForTests() => _events.clear();

  static Object? redactForExport(Object? value) {
    if (value is! Map) return const {'recent_errors': []};
    final events = value['recent_errors'];
    const allowedSources = {
      'flutter',
      'platform',
      'reminders',
      'incoming_share_stream',
      'incoming_share_initial',
      'incoming_share',
      'unknown',
    };
    return {
      'recent_errors': [
        if (events is List)
          for (final event in events.take(_maxEvents))
            if (event is Map)
              {
                'source': allowedSources.contains(event['source'])
                    ? event['source']
                    : 'unknown',
                // Arbitrary exceptions and stacks can contain complete private
                // item content. Pattern redaction cannot prove they are safe.
                'message':
                    'Details withheld to protect item privacy ([uri] [path] [file]).',
                if (DateTime.tryParse(event['captured_at']?.toString() ?? '') !=
                    null)
                  'captured_at': event['captured_at'],
              },
      ],
    };
  }

  static String redactText(String value, {int? maxChars}) {
    final redacted = value
        .replaceAll(RegExp(r'\bcontent://[^ \n\t,;]+'), '[uri]')
        .replaceAll(RegExp(r'\bfile://[^ \n\t,;]+'), '[uri]')
        .replaceAll(RegExp(r'\bhttps?://[^ \n\t,;]+'), '[url]')
        .replaceAll(RegExp(r'\b[A-Za-z]:\\[^ \n\t,;]+'), '[path]')
        .replaceAll(RegExp(r'/[^ \n\t,;]+'), '[path]')
        .replaceAll(
          RegExp(
            r'\b[^\s/\\]+\.(?:pdf|png|jpe?g|gif|heic|webp|txt|docx?|xlsx?|pptx?|csv|zip|json)\b',
            caseSensitive: false,
          ),
          '[file]',
        )
        .replaceAll(RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+'), '[email]');
    if (maxChars == null || redacted.length <= maxChars) return redacted;
    return '${redacted.substring(0, maxChars)}...';
  }

  String _take(String value, int maxChars) =>
      value.length <= maxChars ? value : value.substring(0, maxChars);
}

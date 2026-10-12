import 'dart:convert';

class PendingShareFile {
  const PendingShareFile({
    required this.path,
    this.originalName,
    this.mimeType,
    this.uti,
    this.size,
    this.available = true,
  });

  final String path;
  final String? originalName;
  final String? mimeType;
  final String? uti;
  final int? size;
  final bool available;

  factory PendingShareFile.fromJson(Map<String, Object?> json) {
    return PendingShareFile(
      path: json['path'] as String? ?? '',
      originalName: json['originalName'] as String?,
      mimeType: json['mimeType'] as String?,
      uti: json['uti'] as String?,
      size: json['size'] is num ? (json['size'] as num).toInt() : null,
      available: json['available'] as bool? ?? true,
    );
  }

  Map<String, Object?> toJson() => {
    'path': path,
    if (originalName != null) 'originalName': originalName,
    if (mimeType != null) 'mimeType': mimeType,
    if (uti != null) 'uti': uti,
    if (size != null) 'size': size,
    'available': available,
  };
}

class PendingShareEvent {
  const PendingShareEvent({
    required this.id,
    required this.createdAt,
    required this.source,
    this.text,
    this.url,
    this.files = const [],
  });

  final String id;
  final int createdAt;
  final String source;
  final String? text;
  final String? url;
  final List<PendingShareFile> files;

  bool get hasText => (text?.trim().isNotEmpty ?? false);
  bool get hasUrl => (url?.trim().isNotEmpty ?? false);
  bool get hasFiles => files.isNotEmpty;

  String? get combinedText {
    final parts = <String>[
      if (url?.trim().isNotEmpty ?? false) url!.trim(),
      if (text?.trim().isNotEmpty ?? false) text!.trim(),
    ];
    return parts.isEmpty ? null : parts.join('\n');
  }

  bool get isUrl => hasUrl && !hasText;

  factory PendingShareEvent.fromJson(Map<String, Object?> json) {
    return PendingShareEvent(
      id: json['id'] as String? ?? '',
      createdAt: json['createdAt'] is num
          ? (json['createdAt'] as num).toInt()
          : 0,
      source: json['source'] as String? ?? 'iosShareExtension',
      text: json['text'] as String?,
      url: json['url'] as String?,
      files: (json['files'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<String, Object?>>()
          .map(PendingShareFile.fromJson)
          .toList(),
    );
  }

  factory PendingShareEvent.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Pending share manifest must be an object');
    }
    late final PendingShareEvent event;
    try {
      event = PendingShareEvent.fromJson(decoded);
    } on TypeError {
      throw const FormatException(
        'Pending share manifest has invalid field types',
      );
    }
    if (event.id.trim().isEmpty) {
      throw const FormatException('Pending share manifest is missing id');
    }
    if (!event.hasText && !event.hasUrl && !event.hasFiles) {
      throw const FormatException('Pending share manifest has no content');
    }
    return event;
  }

  Map<String, Object?> toJson() => {
    'schema_version': 'stillopen_pending_share_v1',
    'id': id,
    'createdAt': createdAt,
    'source': source,
    if (text != null) 'text': text,
    if (url != null) 'url': url,
    'files': files.map((file) => file.toJson()).toList(),
  };
}

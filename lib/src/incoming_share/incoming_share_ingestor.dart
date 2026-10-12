import 'dart:io';

import '../controller.dart';
import '../diagnostics.dart';
import 'incoming_share_models.dart';
import 'ios_pending_share_store.dart';

class IncomingShareIngestor {
  IncomingShareIngestor({
    required this.controller,
    required this.store,
    StillOpenDiagnostics? diagnostics,
  }) : _diagnostics = diagnostics ?? StillOpenDiagnostics.instance;

  final StillOpenController controller;
  final PendingShareStore store;
  final StillOpenDiagnostics _diagnostics;
  final Set<String> _processedEventIds = {};
  bool _running = false;

  Future<int> ingestPendingShares() async {
    if (_running) return 0;
    _running = true;
    var created = 0;
    try {
      final manifests = await store.listPendingManifests();
      for (final manifest in manifests) {
        if (_processedEventIds.contains(manifest.event.id)) {
          await store.markProcessed(manifest);
          continue;
        }
        try {
          final report = await _ingest(manifest.event);
          if (report.saved) created += 1;
          if (report.canAcknowledge) {
            _processedEventIds.add(manifest.event.id);
            await store.markProcessed(manifest);
          }
        } on Object catch (error, stackTrace) {
          _recordError(error, stackTrace);
          // The manifest is valid; a copy/preferences failure is retryable.
          // Keep it pending so the next foreground/resume can retry it.
        }
      }
      return created;
    } finally {
      _running = false;
    }
  }

  Future<CaptureReport> _ingest(PendingShareEvent event) {
    final text = event.combinedText;
    return controller.captureSharedContent(
      text: text,
      eventId: event.id,
      isUrl: event.hasUrl,
      files: event.files.map(_incomingFile).toList(),
    );
  }

  IncomingSharedFile _incomingFile(PendingShareFile file) {
    final lowerName = (file.originalName ?? file.path).toLowerCase();
    final mime = file.mimeType?.toLowerCase() ?? '';
    final isImage =
        mime.startsWith('image/') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.heic');
    return IncomingSharedFile(
      path: file.available && File(file.path).existsSync() ? file.path : '',
      mimeType: file.mimeType,
      name: file.available
          ? file.originalName
          : (isImage ? 'Shared image unavailable' : 'Shared file unavailable'),
      isImage: isImage,
      metadataOnly: !file.available || !File(file.path).existsSync(),
      permanentlyUnavailable: !file.available,
    );
  }

  void _recordError(Object error, StackTrace stackTrace) {
    _diagnostics.recordError(
      source: 'ios_pending_share_ingest',
      message: error.toString(),
      stack: stackTrace.toString(),
    );
  }
}

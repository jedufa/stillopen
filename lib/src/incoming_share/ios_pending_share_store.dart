import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'incoming_share_models.dart';

abstract class PendingShareStore {
  Future<List<PendingShareManifest>> listPendingManifests();
  Future<void> markProcessed(PendingShareManifest manifest);
  Future<void> markFailed(PendingShareManifest manifest);
}

class PendingShareManifest {
  const PendingShareManifest({required this.file, required this.event});

  final File file;
  final PendingShareEvent event;
}

class DirectoryPendingShareStore implements PendingShareStore {
  DirectoryPendingShareStore(this.directory);

  final Directory directory;

  @override
  Future<List<PendingShareManifest>> listPendingManifests() async {
    final queue = Directory('${directory.path}/pending_shares');
    if (!queue.existsSync()) return const [];
    final manifests = <PendingShareManifest>[];
    for (final entity in queue.listSync().whereType<File>()) {
      if (!entity.path.endsWith('.json')) continue;
      try {
        final event = PendingShareEvent.fromJsonString(
          await entity.readAsString(),
        );
        manifests.add(PendingShareManifest(file: entity, event: event));
      } on FormatException {
        await markFailed(
          PendingShareManifest(
            file: entity,
            event: PendingShareEvent(
              id: entity.uri.pathSegments.last,
              createdAt: 0,
              source: 'iosShareExtension',
              text: 'invalid',
            ),
          ),
        );
      }
    }
    manifests.sort((a, b) => a.event.createdAt.compareTo(b.event.createdAt));
    return manifests;
  }

  @override
  Future<void> markProcessed(PendingShareManifest manifest) async {
    await _deleteManifestAndFiles(manifest);
  }

  @override
  Future<void> markFailed(PendingShareManifest manifest) async {
    final failed = Directory('${directory.path}/failed_shares');
    if (!failed.existsSync()) failed.createSync(recursive: true);
    if (manifest.file.existsSync()) {
      final target = File(
        '${failed.path}/${manifest.file.uri.pathSegments.last}',
      );
      if (target.existsSync()) target.deleteSync();
      await manifest.file.rename(target.path);
    }
  }

  Future<void> _deleteManifestAndFiles(PendingShareManifest manifest) async {
    for (final file in manifest.event.files) {
      final shared = File(file.path);
      if (_isInsideDirectory(shared, directory) && shared.existsSync()) {
        try {
          await shared.delete();
        } on Object {
          // Best-effort cleanup. The copied app-local attachment is already
          // persisted before this method is called.
        }
      }
    }
    if (manifest.file.existsSync()) await manifest.file.delete();
  }

  bool _isInsideDirectory(File file, Directory parent) {
    try {
      final parentPath = parent.resolveSymbolicLinksSync();
      final filePath = file.resolveSymbolicLinksSync();
      return filePath.startsWith('$parentPath${Platform.pathSeparator}');
    } on FileSystemException {
      return false;
    }
  }
}

class MethodChannelPendingShareStore extends DirectoryPendingShareStore {
  MethodChannelPendingShareStore._(super.directory);

  static const _channel = MethodChannel('stillopen/ios_pending_shares');

  static Future<MethodChannelPendingShareStore?> create() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    final path = await _channel.invokeMethod<String>(
      'getAppGroupPendingShareDirectory',
    );
    if (path == null || path.trim().isEmpty) return null;
    return MethodChannelPendingShareStore._(Directory(path));
  }
}

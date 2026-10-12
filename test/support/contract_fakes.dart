import 'dart:io';

import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/models.dart';

class MemoryContractStore implements StillOpenStore {
  final values = <String, String>{};
  bool failNextWrite = false;
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const FileSystemException('Synthetic storage unavailable');
    }
    values[key] = value;
  }
}

// A filesystem-backed test adapter, not a substitute for the native preferences
// integration suite. New instances read the same bytes instead of sharing a map.
class FileContractStore implements StillOpenStore {
  FileContractStore(this.directory);
  final Directory directory;
  bool failNextWrite = false;
  @override
  Future<String?> getString(String key) async {
    final file = File('${directory.path}/$key');
    return file.existsSync() ? file.readAsString() : null;
  }

  @override
  Future<void> setString(String key, String value) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const FileSystemException('Synthetic storage unavailable');
    }
    directory.createSync(recursive: true);
    final stage = File('${directory.path}/$key.tmp');
    await stage.writeAsString(value, flush: true);
    await stage.rename('${directory.path}/$key');
  }
}

class RecordingReminders implements ReminderScheduler {
  final scheduled = <int, DateTime>{};
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<void> schedule(StillOpenItem item, DateTime when) async =>
      scheduled[item.id] = when;
  @override
  Future<void> cancel(int itemId) async => scheduled.remove(itemId);
  @override
  Future<void> cancelAll() async => scheduled.clear();
}

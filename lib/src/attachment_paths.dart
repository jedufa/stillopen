import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

Future<Directory> applicationAttachmentDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  return Directory(p.join(documents.path, 'attachments'));
}

/// Storage locators are relative to the app's current attachment directory.
/// Public models retain resolved paths for pickers/viewers and portable backup
/// export. The legacy `uri` field remains readable by older snapshot readers.
class AttachmentPaths {
  AttachmentPaths(Directory directory)
    : root = p.normalize(directory.absolute.path);
  final String root;

  Map<String, Object?> encode(ItemAttachment attachment) {
    final json = attachment.toJson();
    final file = _filePath(attachment.uri);
    if (file != null && p.isWithin(root, file)) {
      json['localPath'] = p.posix.joinAll(
        p.split(p.relative(file, from: root)),
      );
    }
    return json;
  }

  ItemAttachment decode(Map<String, Object?> json) {
    final attachment = ItemAttachment.fromJson(json);
    final stored = json['localPath'];
    if (stored != null) {
      if (stored is! String || !_safeRelativePath(stored)) {
        throw const FormatException('Invalid local attachment path.');
      }
      return attachment.copyWith(
        uri: p.joinAll([root, ...p.posix.split(stored)]),
      );
    }
    // Pre-localPath iOS snapshots used an OS-owned container UUID. Recover only
    // this known historical layout, and only when the same relative proof exists
    // in the current app directory. Never search arbitrary filenames/locations.
    final file = _filePath(attachment.uri);
    if (file != null && !File(file).existsSync()) {
      final match = RegExp(
        r'/Containers/Data/Application/[^/]+/Documents/attachments/(.+)$',
      ).firstMatch(file);
      final relative = match?.group(1);
      if (relative != null && _safeRelativePath(relative)) {
        final relocated = p.joinAll([root, ...p.posix.split(relative)]);
        if (File(relocated).existsSync()) {
          return attachment.copyWith(uri: relocated);
        }
      }
    }
    return attachment;
  }

  bool _safeRelativePath(String path) =>
      path.isNotEmpty &&
      !path.contains('\\') &&
      !path.contains(':') &&
      !path.contains('\u0000') &&
      !p.posix.isAbsolute(path) &&
      path
          .split('/')
          .every((part) => part.isNotEmpty && part != '.' && part != '..');

  String? _filePath(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.hasScheme && uri.scheme != 'file') return null;
    final path = uri.hasScheme ? uri.toFilePath() : value;
    return p.isAbsolute(path) ? p.normalize(path) : null;
  }
}

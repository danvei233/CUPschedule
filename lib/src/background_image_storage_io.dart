import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

class StoredBackgroundImage {
  const StoredBackgroundImage({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;
}

Future<StoredBackgroundImage> persistBackgroundImage(
  XFile source, {
  String? previousPath,
}) async {
  final bytes = await source.readAsBytes();
  if (bytes.isEmpty) {
    throw StateError('所选图片为空');
  }
  if (bytes.length > 20 * 1024 * 1024) {
    throw StateError('背景图片不能超过 20 MB');
  }
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    codec.dispose();
  } on Object {
    throw StateError('无法读取所选图片');
  }

  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final extension = _safeExtension(source.name);
  final target = File(
    '${directory.path}${Platform.pathSeparator}background$extension',
  );
  await target.writeAsBytes(bytes, flush: true);
  if (previousPath != null && previousPath != target.path) {
    await _deleteIfPresent(previousPath);
  }
  return StoredBackgroundImage(path: target.path, bytes: bytes);
}

Future<Uint8List?> readBackgroundImage(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return null;
  }
  return file.readAsBytes();
}

Future<void> deleteBackgroundImage(String? path) async {
  if (path != null) {
    await _deleteIfPresent(path);
  }
}

Future<void> _deleteIfPresent(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

String _safeExtension(String name) {
  final match = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(name);
  final extension = match?.group(1)?.toLowerCase();
  const supported = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};
  return extension != null && supported.contains(extension)
      ? '.$extension'
      : '.img';
}

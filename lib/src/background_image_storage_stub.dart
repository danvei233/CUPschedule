import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class StoredBackgroundImage {
  const StoredBackgroundImage({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;
}

Future<StoredBackgroundImage> persistBackgroundImage(
  XFile source, {
  String? previousPath,
}) {
  throw UnsupportedError('当前平台暂不支持保存自定义背景');
}

Future<Uint8List?> readBackgroundImage(String path) async => null;

Future<void> deleteBackgroundImage(String? path) async {}

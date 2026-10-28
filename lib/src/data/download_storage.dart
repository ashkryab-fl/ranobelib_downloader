import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';

class DownloadStorage {
  static const _channel = MethodChannel('app.ranobelib/downloads');
  Future<SavedBook> save(Uint8List bytes, String filename) async {
    final temp = await getTemporaryDirectory();
    final folder = await temp.createTemp('ranobelib-epub-');
    final file = File('${folder.path}/book.epub');
    try {
      await file.writeAsBytes(bytes, flush: true);
      final result = await _channel.invokeMapMethod<String, String>('save', {
        'path': file.path,
        'name': filename,
      });
      if (result == null || result['uri'] == null || result['name'] == null) {
        throw const FileSystemException('Не удалось сохранить EPUB.');
      }
      return SavedBook(result['uri']!, result['name']!);
    } finally {
      await folder.delete(recursive: true);
    }
  }

  Future<void> open(SavedBook book) =>
      _channel.invokeMethod<void>('open', {'uri': book.uri});
}

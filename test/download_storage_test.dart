import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranobeli_downloader/src/data/download_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const downloads = MethodChannel('app.ranobelib/downloads');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ranobelib-storage-test-');
    messenger.setMockMethodCallHandler(paths, (_) async => temp.path);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(downloads, null);
    messenger.setMockMethodCallHandler(paths, null);
    await temp.delete(recursive: true);
  });
  test(
    'storage bridge passes a complete file and cleans temporary data',
    () async {
      String? sourcePath;
      messenger.setMockMethodCallHandler(downloads, (call) async {
        expect(call.method, 'save');
        sourcePath = call.arguments['path'] as String;
        expect(await File(sourcePath!).readAsBytes(), [1, 2, 3]);
        expect(call.arguments['name'], 'Book.epub');
        return {'uri': 'content://downloads/1', 'name': 'Book (1).epub'};
      });
      final saved = await DownloadStorage().save(
        Uint8List.fromList([1, 2, 3]),
        'Book.epub',
      );
      expect(saved.location, 'Downloads/ranobelib/Book (1).epub');
      expect(await File(sourcePath!).exists(), isFalse);
      expect(await temp.list().length, 0);
    },
  );
  test('storage failure still removes export temporary files', () async {
    messenger.setMockMethodCallHandler(
      downloads,
      (_) async => throw PlatformException(code: 'SAVE_FAILED'),
    );
    await expectLater(
      DownloadStorage().save(Uint8List.fromList([1]), 'Book.epub'),
      throwsA(isA<PlatformException>()),
    );
    expect(await temp.list().length, 0);
  });
}

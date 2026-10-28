import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:ranobeli_downloader/src/api.dart';
import 'package:ranobeli_downloader/src/controller.dart';
import 'package:ranobeli_downloader/src/download_storage.dart';
import 'package:ranobeli_downloader/src/epub.dart';
import 'package:ranobeli_downloader/src/models.dart';
import 'package:xml/xml.dart';

class MemoryBookStorage extends DownloadStorage {
  final files = <({String name, Uint8List bytes})>[];
  SavedBook? opened;
  int? failAt;

  @override
  Future<SavedBook> save(Uint8List bytes, String filename) async {
    if (files.length == failAt) throw StateError('Storage unavailable');
    files.add((name: filename, bytes: bytes));
    return SavedBook('content://downloads/${files.length}', filename);
  }

  @override
  Future<void> open(SavedBook book) async => opened = book;
}

String archiveText(Archive archive, String path) =>
    utf8.decode(archive.findFile('EPUB/$path')!.content);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DownloadController controller;
  late MemoryBookStorage storage;
  late List<String> requests;
  late List<String?> branchRequests;
  String? failedVolume;

  setUp(() {
    storage = MemoryBookStorage();
    requests = [];
    branchRequests = [];
    failedVolume = null;
    final picture = image.encodePng(image.Image(width: 2, height: 2));
    final api = RanobeApi(
      client: MockClient((request) async {
        if (request.url.host == 'cdn.example') {
          return http.Response.bytes(picture, 200);
        }
        final volume = request.url.queryParameters['volume']!;
        final number = request.url.queryParameters['number']!;
        requests.add('$volume/$number');
        branchRequests.add(request.url.queryParameters['branch_id']);
        return http.Response(
          jsonEncode({
            'data': volume == failedVolume
                ? {}
                : {
                    'content':
                        '<p>Volume $volume chapter $number</p>'
                        '<img src="https://cdn.example/$volume.png">',
                  },
          }),
          volume == failedVolume ? 404 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    controller = DownloadController(api: api, storage: storage);
    controller.novel = Novel(
      '123--novel',
      {
        'id': 123,
        'rus_name': 'Назва &amp; книга',
        'cover': {'default': 'https://cdn.example/cover.png'},
      },
      Chapter.fromResponse([
        for (final (volume, number) in [
          ('10', '1'),
          ('1', '2'),
          ('2', '1'),
          ('1', '1'),
          ('2', '3'),
        ])
          {
            'volume': volume,
            'number': number,
            'branches': [1],
          },
      ]),
    );
    controller.setBranch(null);
  });
  tearDown(() => controller.dispose());

  test('exports one book by default and opens the saved result', () async {
    expect(controller.splitByVolume, isFalse);
    await controller.download();

    expect(controller.error, isNull);
    expect(storage.files.single.name, 'Назва & книга.epub');
    final zip = ZipDecoder().decodeBytes(storage.files.single.bytes);
    expect(
      zip.files.where((f) => f.name.startsWith('EPUB/chapter_')),
      hasLength(5),
    );
    final opf = XmlDocument.parse(archiveText(zip, 'content.opf'));
    expect(opf.findAllElements('dc:title').single.innerText, 'Назва & книга');
    expect(
      opf.findAllElements('dc:identifier').single.innerText,
      'ranobelib-123',
    );
    await controller.openBook(controller.savedBooks.single);
    expect(storage.opened, controller.savedBooks.single);
  });

  test('exports only selected chapters into self-contained volumes', () async {
    controller.setSplitByVolume(true);
    controller.selectAll(false, volume: '10');
    controller.toggle(
      controller.chapters.firstWhere((s) => s.chapter.key == '1/1').chapter,
      false,
    );
    final progress = <int>[];
    controller.addListener(() {
      final update = controller.progress;
      if (update != null) {
        expect(update.total, 3);
        progress.add(update.completed);
      }
    });
    await controller.download();

    expect(controller.error, isNull);
    expect(requests, ['1/2', '2/1', '2/3']);
    expect(storage.files.map((f) => f.name), [
      'Назва & книга — Том 1.epub',
      'Назва & книга — Том 2.epub',
    ]);
    expect(controller.savedBooks, hasLength(2));
    expect(controller.notice, 'Збережено EPUB: 2.');
    expect(progress, orderedEquals([...progress]..sort()));
    expect(progress.last, 3);
    for (var i = 0; i < storage.files.length; i++) {
      final volume = '${i + 1}';
      final zip = ZipDecoder().decodeBytes(
        storage.files[i].bytes,
        verify: true,
      );
      final chapters = zip.files
          .where((f) => f.name.startsWith('EPUB/chapter_'))
          .toList();
      expect(chapters, hasLength(i + 1));
      for (final chapter in chapters) {
        expect(
          utf8.decode(chapter.content),
          contains('Volume $volume chapter'),
        );
      }
      final opf = XmlDocument.parse(archiveText(zip, 'content.opf'));
      expect(
        opf.findAllElements('dc:title').single.innerText,
        'Назва & книга — Том $volume',
      );
      final identifier = opf.findAllElements('dc:identifier').single.innerText;
      expect(identifier, 'ranobelib-123-volume-$volume');
      final ncx = XmlDocument.parse(archiveText(zip, 'toc.ncx'));
      expect(
        ncx.findAllElements('docTitle').single.innerText,
        'Назва & книга — Том $volume',
      );
      expect(
        ncx.findAllElements('meta').first.getAttribute('content'),
        identifier,
      );
      final nav = XmlDocument.parse(archiveText(zip, 'nav.xhtml'));
      expect(nav.findAllElements('a').first.innerText, 'Том $volume');
      expect(zip.findFile('EPUB/cover.xhtml'), isNotNull);
      expect(
        zip.files.where((f) => f.name.startsWith('EPUB/images/')),
        hasLength(2),
      );
      for (final item in opf.findAllElements('item')) {
        expect(zip.findFile('EPUB/${item.getAttribute('href')}'), isNotNull);
      }
    }
    await controller.openBook(controller.savedBooks.first);
    expect(storage.opened, controller.savedBooks.first);
    await controller.openBook(controller.savedBooks.last);
    expect(storage.opened, controller.savedBooks.last);
  });

  test('includes the volume suffix when only one volume is selected', () async {
    controller.setSplitByVolume(true);
    controller.selectAll(false);
    controller.selectAll(true, volume: '10');
    await controller.download();

    expect(controller.error, isNull);
    expect(storage.files.single.name, 'Назва & книга — Том 10.epub');
    expect(requests, ['10/1']);
  });

  test(
    'exports the locally chosen translation for each selected chapter',
    () async {
      final book = controller.novel!;
      controller.novel = Novel(book.slug, book.data, [
        for (final chapter in book.chapters)
          Chapter(chapter.data, [Branch(1), Branch(2)]),
      ]);
      controller.setBranch(null);
      controller.setVolumeBranch('1', '2');
      controller.setChapterBranch('2/1', '2');
      controller.toggleVolumeExpanded('1');
      controller.toggle(
        controller.chapters.firstWhere((s) => s.chapter.key == '2/3').chapter,
        false,
      );
      await controller.download();

      expect(controller.error, isNull);
      expect(requests, ['1/1', '1/2', '2/1', '10/1']);
      expect(branchRequests, ['2', '2', '2', '1']);
      final zip = ZipDecoder().decodeBytes(storage.files.single.bytes);
      expect(
        zip.files.where((f) => f.name.startsWith('EPUB/chapter_')),
        hasLength(4),
      );
    },
  );

  for (final split in [false, true]) {
    test(
      'global branch keeps fallback chapters in EPUB (split: $split)',
      () async {
        final book = controller.novel!;
        controller.novel = Novel(book.slug, book.data, [
          for (final chapter in book.chapters)
            Chapter(
              chapter.data,
              chapter.key == '2/1' ? [Branch(3)] : [Branch(1), Branch(2)],
            ),
        ]);
        controller.setBranch(null);
        controller.toggle(
          controller.chapters.firstWhere((s) => s.chapter.key == '2/3').chapter,
          false,
        );
        controller.setSplitByVolume(split);
        controller.setBranch('2');
        await controller.download();

        expect(controller.error, isNull);
        expect(requests, ['1/1', '1/2', '2/1', '10/1']);
        expect(branchRequests, ['2', '2', '3', '2']);
        expect(storage.files, hasLength(split ? 3 : 1));
        final exportedChapters = storage.files.expand((file) {
          final zip = ZipDecoder().decodeBytes(file.bytes);
          return zip.files.where((f) => f.name.startsWith('EPUB/chapter_'));
        });
        expect(exportedChapters, hasLength(4));
      },
    );
  }

  test('rejects an empty selection without creating any files', () async {
    controller.setSplitByVolume(true);
    controller.selectAll(false);
    await controller.download();

    expect(controller.error, 'Виберіть хоча б одну главу.');
    expect(storage.files, isEmpty);
    expect(requests, isEmpty);
  });

  test('keeps completed volumes when a later chapter is unavailable', () async {
    controller.setSplitByVolume(true);
    failedVolume = '2';
    await controller.download();

    expect(controller.error, isNotNull);
    expect(controller.busy, isFalse);
    expect(storage.files.single.name, 'Назва & книга — Том 1.epub');
    expect(controller.savedBooks.single.name, storage.files.single.name);
    expect(requests, ['1/1', '1/2', '2/1']);
  });

  test('keeps completed volumes when saving a later file fails', () async {
    controller.setSplitByVolume(true);
    storage.failAt = 1;
    await controller.download();

    expect(controller.error, contains('Storage unavailable'));
    expect(controller.busy, isFalse);
    expect(controller.saving, isFalse);
    expect(controller.savedBooks.single.name, 'Назва & книга — Том 1.epub');
    expect(requests, ['1/1', '1/2', '2/1', '2/3']);
  });

  test('cancels between volumes and preserves the completed file', () async {
    controller.setSplitByVolume(true);
    controller.addListener(() {
      if (controller.busy &&
          !controller.saving &&
          controller.savedBooks.isNotEmpty) {
        controller.cancel();
      }
    });
    await controller.download();

    expect(controller.error, isNull);
    expect(controller.notice, 'Завантаження скасовано. Збережено EPUB: 1.');
    expect(controller.savedBooks.single.name, 'Назва & книга — Том 1.epub');
    expect(storage.files, hasLength(1));
    expect(requests, ['1/1', '1/2']);
  });

  test('long filenames preserve distinct volume numbers', () {
    final title = List.filled(150, 'К').join();
    final first = safeBookFilename(title, volume: '1');
    final second = safeBookFilename(title, volume: '1.5');
    expect(first, endsWith(' — Том 1.epub'));
    expect(second, endsWith(' — Том 1.5.epub'));
    expect(first.runes.length, 105);
    expect(second.runes.length, 105);
    expect(safeBookFilename('A/B:*?', volume: '2'), 'AB — Том 2.epub');
  });
}

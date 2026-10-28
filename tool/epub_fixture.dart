import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:ranobeli_downloader/src/content.dart';
import 'package:ranobeli_downloader/src/epub.dart';
import 'package:ranobeli_downloader/src/models.dart';

/// Generates a synthetic book for independent EPUBCheck validation. No network.
Future<void> main(List<String> arguments) async {
  final chapters = Chapter.fromResponse([
    {
      'volume': '1',
      'number': '1',
      'name': 'Текст &amp; ілюстрація',
      'branches': [1],
    },
    {
      'volume': '2',
      'number': '1',
      'name': 'Другий том',
      'branches': [1],
    },
  ]);
  final novel = Novel('123--fixture', {
    'id': 123,
    'rus_name': 'EPUB &amp; перевірка (Новелла)',
    'authors': [
      {'name': 'Test Author'},
    ],
    'summary': {
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {'type': 'text', 'text': 'Synthetic validation book.'},
          ],
        },
      ],
    },
    'genres': [
      {'name': 'Fantasy'},
    ],
    'releaseDateString': '2020',
  }, chapters);
  final prepared = <PreparedChapter>[];
  for (final chapter in chapters) {
    final body = await ContentParser().prepare(
      '<p>A &amp; B<br><strong>Text</strong></p>'
      '<img src="https://example.com/image.jpg" alt="Illustration">',
      (_) async => 'picture.jpg',
    );
    prepared.add(PreparedChapter(chapter, body));
  }
  final picture = image.encodeJpg(image.Image(width: 16, height: 16));
  final bytes = buildEpub(
    EpubInput(novel, prepared, [
      BookImage('picture.jpg', 'image/jpeg', picture),
    ], BookImage('cover.jpg', 'image/jpeg', picture)),
  );
  final file = File(
    arguments.isEmpty ? 'build/verification/fixture.epub' : arguments.single,
  );
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  stdout.writeln(file.absolute.path);
}

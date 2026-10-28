import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'content.dart';
import '../domain/models.dart';

class EpubInput {
  const EpubInput(
    this.novel,
    this.chapters,
    this.images,
    this.cover, {
    this.volume,
  });
  final Novel novel;
  final List<PreparedChapter> chapters;
  final List<BookImage> images;
  final BookImage? cover;
  final String? volume;
  String get title =>
      volume == null ? novel.title : '${novel.title} — Том $volume';
  String get identifier =>
      'ranobelib-${novel.id}'
      '${volume == null ? '' : '-volume-${Uri.encodeComponent(volume!)}'}';
}

String _document(String title, String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" lang="ru" xml:lang="ru">'
    '<head><title>${xmlEscape(title)}</title><link href="style.css" rel="stylesheet" type="text/css"/></head>'
    '<body>$body</body></html>';

String _filenamePart(String value) => value
    .replaceAll(RegExp(r'[\\/*?:"<>|\x00-\x1f]'), '')
    .trim()
    .replaceAll(RegExp(r'[. ]+$'), '');

String safeBookFilename(String title, {String? volume}) {
  final clean = _filenamePart(title);
  final suffix = volume == null
      ? ''
      : ' — Том ${String.fromCharCodes(_filenamePart(volume).runes.take(60))}';
  final runes = (clean.isEmpty ? 'RanobeLIB' : clean).runes.take(
    100 - suffix.runes.length,
  );
  return '${String.fromCharCodes(runes).trimRight()}$suffix.epub';
}

/// EPUB 3 with EPUB 2 NCX compatibility. The mimetype is first and uncompressed.
Uint8List buildEpub(EpubInput input) {
  if (input.chapters.isEmpty) {
    throw const FormatException('Не выбрано ни одной главы.');
  }
  final archive = Archive();
  void add(String name, List<int> bytes, {bool compress = true}) {
    archive.addFile(
      ArchiveFile(name, bytes.length, bytes)
        ..compression = compress
            ? CompressionType.deflate
            : CompressionType.none,
    );
  }

  void addText(String name, String text, {bool compress = true}) =>
      add(name, utf8.encode(text), compress: compress);
  addText('mimetype', 'application/epub+zip', compress: false);
  addText(
    'META-INF/container.xml',
    '<?xml version="1.0"?>'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  addText(
    'EPUB/style.css',
    'body { line-height: 1.5; } p { margin: 0.6em 0; } '
        'img { max-width: 100%; height: auto; } h1 { text-align: center; } '
        'table { border-collapse: collapse; max-width: 100%; } td, th { border: 1px solid; padding: 0.3em; } '
        'pre { white-space: pre-wrap; }',
  );
  final chapters = input.chapters;
  final volumes = <String, List<int>>{};
  for (var i = 0; i < chapters.length; i++) {
    final ch = chapters[i];
    (volumes[ch.chapter.volume] ??= []).add(i);
    addText(
      'EPUB/chapter_${i + 1}.xhtml',
      _document(
        ch.chapter.title,
        '<h1>${xmlEscape(ch.chapter.title)}</h1>${ch.xhtml}',
      ),
    );
  }
  for (final image in input.images) {
    add('EPUB/images/${image.name}', image.bytes);
  }
  final cover = input.cover;
  if (cover != null) {
    add('EPUB/images/${cover.name}', cover.bytes);
    addText(
      'EPUB/cover.xhtml',
      _document(
        'Обложка',
        '<div><img src="images/${xmlEscape(cover.name)}" alt="Обложка"/></div>',
      ),
    );
  }

  final nav = StringBuffer(
    '<nav xmlns:epub="http://www.idpf.org/2007/ops" epub:type="toc" id="toc"><h1>Содержание</h1><ol>',
  );
  for (final volume in volumes.entries) {
    nav.write(
      '<li><a href="chapter_${volume.value.first + 1}.xhtml">Том ${xmlEscape(volume.key)}</a><ol>',
    );
    for (final i in volume.value) {
      nav.write(
        '<li><a href="chapter_${i + 1}.xhtml">${xmlEscape(chapters[i].chapter.title)}</a></li>',
      );
    }
    nav.write('</ol></li>');
  }
  nav.write('</ol></nav>');
  addText('EPUB/nav.xhtml', _document('Содержание', nav.toString()));

  final ncx = XmlBuilder();
  ncx.processing('xml', 'version="1.0" encoding="UTF-8"');
  ncx.element(
    'ncx',
    attributes: {
      'xmlns': 'http://www.daisy.org/z3986/2005/ncx/',
      'version': '2005-1',
    },
    nest: () {
      ncx.element(
        'head',
        nest: () {
          for (final entry in {
            'dtb:uid': input.identifier,
            'dtb:depth': '2',
            'dtb:totalPageCount': '0',
            'dtb:maxPageNumber': '0',
          }.entries) {
            ncx.element(
              'meta',
              attributes: {'name': entry.key, 'content': entry.value},
            );
          }
        },
      );
      ncx.element(
        'docTitle',
        nest: () => ncx.element('text', nest: input.title),
      );
      ncx.element(
        'navMap',
        nest: () {
          var order = 0;
          final targetOrders = <int, int>{};
          void point(
            String id,
            String title,
            int i,
            void Function()? children,
          ) {
            ncx.element(
              'navPoint',
              attributes: {
                'id': id,
                'playOrder': '${targetOrders.putIfAbsent(i, () => ++order)}',
              },
              nest: () {
                ncx.element(
                  'navLabel',
                  nest: () => ncx.element('text', nest: title),
                );
                ncx.element(
                  'content',
                  attributes: {'src': 'chapter_${i + 1}.xhtml'},
                );
                children?.call();
              },
            );
          }

          var v = 0;
          for (final volume in volumes.entries) {
            point('volume-${++v}', 'Том ${volume.key}', volume.value.first, () {
              for (final i in volume.value) {
                point('chapter-${i + 1}', chapters[i].chapter.title, i, null);
              }
            });
          }
        },
      );
    },
  );
  addText('EPUB/toc.ncx', ncx.buildDocument().toXmlString());

  final opf = XmlBuilder();
  opf.processing('xml', 'version="1.0" encoding="UTF-8"');
  opf.element(
    'package',
    attributes: {
      'xmlns': 'http://www.idpf.org/2007/opf',
      'version': '3.0',
      'unique-identifier': 'book-id',
    },
    nest: () {
      opf.element(
        'metadata',
        attributes: {'xmlns:dc': 'http://purl.org/dc/elements/1.1/'},
        nest: () {
          opf.element(
            'dc:identifier',
            attributes: {'id': 'book-id'},
            nest: input.identifier,
          );
          opf.element('dc:title', nest: input.title);
          opf.element('dc:language', nest: 'ru');
          if (input.novel.author.isNotEmpty) {
            opf.element('dc:creator', nest: input.novel.author);
          }
          final summary = ContentParser().summaryText(
            input.novel.data['summary'],
          );
          if (summary.isNotEmpty) opf.element('dc:description', nest: summary);
          for (final subject in input.novel.subjects) {
            opf.element('dc:subject', nest: subject);
          }
          final year = RegExp(
            r'\d{4}',
          ).firstMatch(textOf(input.novel.data['releaseDateString']))?.group(0);
          if (year != null) opf.element('dc:date', nest: year);
          opf.element(
            'meta',
            attributes: {'property': 'dcterms:modified'},
            nest:
                '${DateTime.now().toUtc().toIso8601String().split('.').first}Z',
          );
          if (cover != null) {
            opf.element(
              'meta',
              attributes: {'name': 'cover', 'content': 'cover-image'},
            );
          }
        },
      );
      opf.element(
        'manifest',
        nest: () {
          void item(String id, String href, String mime, [String? properties]) {
            opf.element(
              'item',
              attributes: {
                'id': id,
                'href': href,
                'media-type': mime,
                'properties': ?properties,
              },
            );
          }

          item('nav', 'nav.xhtml', 'application/xhtml+xml', 'nav');
          item('ncx', 'toc.ncx', 'application/x-dtbncx+xml');
          item('style', 'style.css', 'text/css');
          if (cover != null) {
            item(
              'cover-image',
              'images/${cover.name}',
              cover.mime,
              'cover-image',
            );
            item('cover-page', 'cover.xhtml', 'application/xhtml+xml');
          }
          for (var i = 0; i < chapters.length; i++) {
            item(
              'chapter-${i + 1}',
              'chapter_${i + 1}.xhtml',
              'application/xhtml+xml',
            );
          }
          for (var i = 0; i < input.images.length; i++) {
            item(
              'image-$i',
              'images/${input.images[i].name}',
              input.images[i].mime,
            );
          }
        },
      );
      opf.element(
        'spine',
        attributes: {'toc': 'ncx'},
        nest: () {
          if (cover != null) {
            opf.element('itemref', attributes: {'idref': 'cover-page'});
          }
          for (var i = 0; i < chapters.length; i++) {
            opf.element('itemref', attributes: {'idref': 'chapter-${i + 1}'});
          }
        },
      );
      if (cover != null) {
        opf.element(
          'guide',
          nest: () {
            opf.element(
              'reference',
              attributes: {
                'type': 'cover',
                'title': 'Обложка',
                'href': 'cover.xhtml',
              },
            );
          },
        );
      }
    },
  );
  addText('EPUB/content.opf', opf.buildDocument().toXmlString());
  return ZipEncoder().encodeBytes(archive);
}

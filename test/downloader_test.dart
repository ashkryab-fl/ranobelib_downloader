import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:ranobeli_downloader/src/api.dart';
import 'package:ranobeli_downloader/src/auth.dart';
import 'package:ranobeli_downloader/src/content.dart';
import 'package:ranobeli_downloader/src/controller.dart';
import 'package:ranobeli_downloader/src/downloader.dart';
import 'package:ranobeli_downloader/src/epub.dart';
import 'package:ranobeli_downloader/src/models.dart';
import 'package:xml/xml.dart';

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json rawChapter(
  String volume,
  String number,
  List<dynamic> branches, {
  int index = 0,
}) => {
  'volume': volume,
  'number': number,
  'name': 'Назва &amp; текст',
  'index': index,
  'branches': branches,
};
Json branch(int id, {bool restricted = false, int moderation = 1}) => {
  'branch_id': id,
  'moderation': {'id': moderation},
  'restricted_view': {'is_open': !restricted},
  'teams': [
    {'name': 'Команда $id'},
  ],
};

class MemoryTokenStore implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('book URLs validate the host and preserve the slug', () {
    expect(
      extractSlug(' https://ranobelib.me/ru/book/123--novel?section=chapters '),
      '123--novel',
    );
    expect(
      extractSlug('https://ranobelib.org/ru/book/123--novel'),
      '123--novel',
    );
    for (final invalid in [
      'https://evil.example/ru/book/123--novel',
      'https://ranobelib.me.evil.example/ru/book/123--novel',
      'https://user@ranobelib.me/ru/book/123--novel',
      'http://ranobelib.me/ru/book/123--novel',
      'https://ranobelib.me/ru/book/../../auth',
      'https://ranobelib.me/ru/book/a%2Fb',
      'https://ranobelib.me/ru/book/',
      '',
    ]) {
      expect(
        () => extractSlug(invalid),
        throwsFormatException,
        reason: invalid,
      );
    }
  });

  test('moderation and closed branches are filtered like Python', () {
    final chapters = Chapter.fromResponse([
      rawChapter('1', '1', [branch(1), branch(2, restricted: true)]),
      rawChapter('1', '2', [branch(1, moderation: 0), branch(2)]),
      rawChapter('1', '3', [branch(2, restricted: true)]),
      rawChapter('1', '4', []),
      rawChapter('1', '5', [7]),
    ]);
    expect(chapters.map((c) => c.number), ['1', '5']);
    expect(chapters.first.branches.map((b) => b.id), ['1']);
    expect(chapters.last.branches.single.id, '7');
  });

  test(
    'automatic branch selection fills gaps, deduplicates and orders volumes',
    () {
      final novel = Novel(
        '123--novel',
        {},
        Chapter.fromResponse([
          rawChapter('1', '1', [branch(2), branch(1)]),
          rawChapter('1', '2', [branch(1), branch(2)]),
          rawChapter('1', '3', [branch(1)]),
          rawChapter('1', '2', [branch(2)]),
          rawChapter('2', '1', [branch(1)]),
          rawChapter('1', '10', [branch(1)]),
          rawChapter('1', '2.5', [branch(2)]),
        ]),
      );
      final selected = novel.selectBranch(null);
      expect(selected.map((s) => s.chapter.key), [
        '1/1',
        '1/2',
        '1/2.5',
        '1/3',
        '1/10',
        '2/1',
      ]);
      expect(selected.take(3).map((s) => s.branch.id), ['2', '2', '2']);
      expect(novel.selectBranch('2').map((s) => s.chapter.number), [
        '1',
        '2',
        '2.5',
      ]);
      expect(novel.branchNames['1'], 'Команда 1');
    },
  );

  test(
    'content renders marks, attachments, lists and escaped text as valid XML',
    () async {
      final parser = ContentParser();
      final raw = parser.chapterHtml({
        'content': {
          'type': 'doc',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {
                  'type': 'text',
                  'text': 'A &amp; &lt;B&gt;\nNext',
                  'marks': [
                    {'type': 'bold'},
                    {'type': 'italic'},
                  ],
                },
              ],
            },
            {
              'type': 'bulletList',
              'content': [
                {
                  'type': 'listItem',
                  'content': [
                    {'type': 'text', 'text': 'List'},
                  ],
                },
              ],
            },
            {
              'type': 'image',
              'attrs': {
                'images': [
                  {'image': 'illustration'},
                ],
              },
            },
          ],
        },
        'attachments': [
          {'name': 'illustration', 'url': 'https://cdn.example/image.png'},
        ],
      });
      final urls = <String>[];
      final prepared = await parser.prepare(raw, (url) async {
        urls.add(url);
        return 'picture.jpg';
      });
      final xml = XmlDocument.parse('<body>$prepared</body>');
      expect(
        xml.findAllElements('strong').single.innerText,
        contains('A & <B>'),
      );
      expect(xml.findAllElements('ul'), hasLength(1));
      expect(xml.findAllElements('br'), hasLength(1));
      expect(
        xml.findAllElements('img').single.getAttribute('src'),
        'images/picture.jpg',
      );
      expect(urls, ['https://cdn.example/image.png']);
    },
  );

  test('legacy HTML repairs entities and strips executable elements', () async {
    final prepared = await ContentParser().prepare(
      '<p data-paragraph-index="1">A&nbsp;&amp; B<br><b>text</b></p>'
      '<script>bad()</script><img src="/test.png" onerror="bad()">',
      (_) async => 'test.png',
    );
    final xml = XmlDocument.parse('<body>$prepared</body>');
    expect(xml.findAllElements('img').single.getAttribute('onerror'), isNull);
    expect(xml.findAllElements('script'), isEmpty);
    expect(
      xml.findAllElements('p').single.getAttribute('data-paragraph-index'),
      isNull,
    );
    expect(xml.innerText, contains('A\u00a0& B'));
    expect(decodeEntities('&amp;amp; &lt;text&gt;'), '& <text>');
  });

  test('image compression bounds dimensions and retains transparency', () {
    final original = image.Image(width: 1600, height: 1200, numChannels: 4);
    original.setPixelRgba(0, 0, 255, 0, 0, 100);
    final compressed = compressImage(
      Uint8List.fromList(image.encodePng(original)),
    );
    final decoded = image.decodeImage(Uint8List.fromList(compressed.bytes))!;
    expect(decoded.width, 800);
    expect(decoded.height, 600);
    expect(decoded.hasAlpha, isTrue);
    expect(compressed.mime, 'image/png');
    expect(
      () => compressImage(Uint8List.fromList([0, 1, 2])),
      throwsFormatException,
    );
  });

  test(
    'EPUB has stored mimetype, valid manifest, grouped navigation and cover',
    () {
      final chapters = Chapter.fromResponse([
        rawChapter('1', '1', [1]),
        rawChapter('2', '1', [1]),
      ]);
      final novel = Novel('123--novel', {
        'id': 123,
        'rus_name': 'Назва &amp; книга (Новелла)',
        'authors': [
          {'name': 'Author'},
        ],
        'summary': '<p>Description &amp; more</p>',
        'genres': [
          {'name': 'Fantasy'},
        ],
        'releaseDateString': '2020',
      }, chapters);
      final picture = BookImage(
        'picture.png',
        'image/png',
        image.encodePng(image.Image(width: 5, height: 5)),
      );
      final cover = BookImage(
        'cover.jpg',
        'image/jpeg',
        image.encodeJpg(image.Image(width: 5, height: 5)),
      );
      final bytes = buildEpub(
        EpubInput(
          novel,
          chapters
              .map(
                (c) => PreparedChapter(
                  c,
                  '<p>Text &amp; more</p><img src="images/picture.png"/>',
                ),
              )
              .toList(),
          [picture],
          cover,
        ),
      );
      // Check the ZIP local header directly, independently of ZIP decoding.
      final header = ByteData.sublistView(bytes);
      expect(header.getUint16(8, Endian.little), 0);
      final zip = ZipDecoder().decodeBytes(bytes, verify: true);
      expect(zip.files.first.name, 'mimetype');
      expect(utf8.decode(zip.files.first.content), 'application/epub+zip');
      for (final file in zip.files.where(
        (f) =>
            f.name.endsWith('.xml') ||
            f.name.endsWith('.xhtml') ||
            f.name.endsWith('.opf') ||
            f.name.endsWith('.ncx'),
      )) {
        expect(
          () => XmlDocument.parse(utf8.decode(file.content)),
          returnsNormally,
          reason: file.name,
        );
      }
      final opf = XmlDocument.parse(
        utf8.decode(zip.findFile('EPUB/content.opf')!.content),
      );
      expect(opf.findAllElements('dc:title').single.innerText, 'Назва & книга');
      expect(opf.findAllElements('dc:creator').single.innerText, 'Author');
      final manifest = opf.findAllElements('item').toList();
      for (final item in manifest) {
        expect(zip.findFile('EPUB/${item.getAttribute('href')}'), isNotNull);
      }
      final ids = manifest.map((item) => item.getAttribute('id')).toSet();
      for (final spine in opf.findAllElements('itemref')) {
        expect(ids, contains(spine.getAttribute('idref')));
      }
      final nav = XmlDocument.parse(
        utf8.decode(zip.findFile('EPUB/nav.xhtml')!.content),
      );
      expect(nav.findAllElements('a').map((e) => e.innerText), [
        'Том 1',
        chapters[0].title,
        'Том 2',
        chapters[1].title,
      ]);
      expect(safeBookFilename('A/B:*?"<>|'), 'AB.epub');
      expect(safeBookFilename('...'), 'RanobeLIB.epub');
      final ncx = XmlDocument.parse(
        utf8.decode(zip.findFile('EPUB/toc.ncx')!.content),
      );
      final targetOrders = <String, String?>{};
      for (final point in ncx.findAllElements('navPoint')) {
        final target = point
            .findElements('content')
            .single
            .getAttribute('src')!;
        final order = point.getAttribute('playOrder');
        expect(targetOrders.putIfAbsent(target, () => order), order);
      }
      expect(
        () => buildEpub(EpubInput(novel, [], [], null)),
        throwsFormatException,
      );
    },
  );

  test(
    'OAuth PKCE and state validation reject foreign or mismatched callbacks',
    () {
      final request = OAuthRequest();
      final expected = base64Url
          .encode(sha256.convert(utf8.encode(request.verifier)).bytes)
          .replaceAll('=', '');
      expect(request.url.queryParameters['code_challenge'], expected);
      expect(request.verifier.length, 128);
      final callback = Uri.parse(
        '${OAuthRequest.redirect}?code=good&state=${request.state}',
      );
      expect(request.codeFromCallback(callback), 'good');
      expect(
        () => request.codeFromCallback(
          Uri.parse('${OAuthRequest.redirect}?code=bad&state=wrong'),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => request.codeFromCallback(
          Uri.parse('https://evil.example/?code=good&state=${request.state}'),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => request.codeFromCallback(
          Uri.parse(
            '${OAuthRequest.redirect}?error=access_denied&state=${request.state}',
          ),
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'expired session refreshes once, persists rotation, retries original request',
    () async {
      final store = MemoryTokenStore()
        ..value = jsonEncode({
          'access_token': 'expired',
          'refresh_token': 'refresh',
        });
      var refreshes = 0;
      var reads = 0;
      final api = RanobeApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/token')) {
            refreshes++;
            expect(jsonDecode(request.body)['grant_type'], 'refresh_token');
            return jsonResponse({
              'access_token': 'renewed',
              'refresh_token': 'rotated',
            });
          }
          reads++;
          if (request.headers['Authorization'] == 'Bearer expired') {
            return jsonResponse({}, 401);
          }
          expect(request.headers['Authorization'], 'Bearer renewed');
          return jsonResponse({
            'data': {'id': 1, 'username': 'reader'},
          });
        }),
      );
      addTearDown(api.close);
      final auth = RanobeAuth(api, store: store);
      await auth.restore();
      expect(refreshes, 1);
      expect(reads, 2);
      expect(auth.user?['username'], 'reader');
      expect(jsonDecode(store.value!)['refresh_token'], 'rotated');
    },
  );

  test(
    'direct-token validation failure restores the previous session',
    () async {
      final api = RanobeApi(
        client: MockClient((_) async => jsonResponse({}, 401)),
      )..token = 'previous';
      addTearDown(api.close);
      final store = MemoryTokenStore();
      final auth = RanobeAuth(api, store: store);
      await expectLater(
        auth.directToken('Bearer invalid'),
        throwsA(isA<ApiException>()),
      );
      expect(api.token, 'previous');
      expect(store.value, isNull);
    },
  );

  test('401 invokes login once and 403 never loops authorization', () async {
    var requests = 0;
    var logins = 0;
    final api = RanobeApi(
      client: MockClient((_) async {
        requests++;
        return jsonResponse({}, 401);
      }),
    );
    addTearDown(api.close);
    api.authorize = () async {
      logins++;
      api.token = 'still-invalid';
      return true;
    };
    await expectLater(
      api.getJson(Uri.https(RanobeApi.apiHost, '/api/test'), Cancellation()),
      throwsA(isA<ApiException>()),
    );
    expect(logins, 1);
    expect(requests, 2);
  });

  test(
    'CDN requests and redirects never receive API bearer credentials',
    () async {
      final seen = <http.Request>[];
      final api = RanobeApi(
        client: MockClient((request) async {
          seen.add(request);
          if (request.url.host == RanobeApi.apiHost) {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://cdn.example/image.png'},
            );
          }
          return http.Response.bytes([1, 2, 3], 200);
        }),
      )..token = 'private';
      addTearDown(api.close);
      await api.image('https://${RanobeApi.apiHost}/image.png', Cancellation());
      expect(seen.first.headers['Authorization'], 'Bearer private');
      expect(seen.last.headers['Authorization'], isNull);
    },
  );

  test('cancellation interrupts a pending network request', () async {
    final api = RanobeApi(
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return jsonResponse({'data': {}});
      }),
    );
    addTearDown(api.close);
    final cancel = Cancellation();
    final request = api.getJson(
      Uri.https(RanobeApi.apiHost, '/api/test'),
      cancel,
    );
    cancel.cancel();
    await expectLater(request, throwsA(isA<DownloadCancelled>()));
  });

  test(
    'mock API to EPUB embeds cover and deduplicates repeated chapter images',
    () async {
      final picture = image.encodeJpg(image.Image(width: 20, height: 10));
      var imageRequests = 0;
      final api = RanobeApi(
        client: MockClient((request) async {
          expect(request.headers['Site-Id'], '3');
          if (request.url.host == 'cdn.example') {
            expect(request.headers['Authorization'], isNull);
            imageRequests++;
            return http.Response.bytes(picture, 200);
          }
          if (request.url.path.endsWith('/chapters')) {
            return jsonResponse({
              'data': [
                rawChapter('1', '1', [branch(42)]),
                rawChapter('2', '1', [branch(42)]),
              ],
            });
          }
          if (request.url.path.endsWith('/chapter')) {
            expect(request.url.queryParameters['branch_id'], '42');
            return jsonResponse({
              'data': {
                'content':
                    '<p>Читаємо &amp; зберігаємо</p><img src="https://cdn.example/picture.jpg">',
              },
            });
          }
          expect(
            request.url.queryParametersAll['fields[]'],
            contains('authors'),
          );
          return jsonResponse({
            'data': {
              'id': 123,
              'rus_name': 'Тест',
              'cover': {'default': 'https://cdn.example/cover.jpg'},
            },
          });
        }),
      );
      addTearDown(api.close);
      final novel = await api.loadNovel('123--novel', Cancellation());
      final updates = <DownloadProgress>[];
      final bytes = await BookDownloader(
        api,
      ).download(novel, novel.selectBranch(null), Cancellation(), updates.add);
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(imageRequests, 2); // cover plus one unique illustration
      expect(
        zip.files.where((f) => f.name.startsWith('EPUB/images/')),
        hasLength(2),
      );
      expect(
        zip.files.where((f) => f.name.startsWith('EPUB/chapter_')),
        hasLength(2),
      );
      expect(updates.last.message, 'Створення EPUB…');
      expect(updates.last.completed, 2);
      final chapterText = utf8.decode(
        zip.findFile('EPUB/chapter_1.xhtml')!.content,
      );
      expect(chapterText, contains('Читаємо &amp; зберігаємо'));
      expect(chapterText, isNot(contains('Переводчик:')));
    },
  );

  test(
    'controller selects volumes and drops stale account-dependent chapters',
    () async {
      final api = RanobeApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/chapters')) {
            return jsonResponse({
              'data': [
                rawChapter('1', '1', [1]),
                rawChapter('1', '2', [1]),
                rawChapter('2', '1', [1]),
              ],
            });
          }
          if (request.url.path.contains('missing')) {
            return jsonResponse({}, 404);
          }
          return jsonResponse({
            'data': {'id': 123, 'rus_name': 'Test'},
          });
        }),
      );
      final controller = DownloadController(
        api: api,
        tokenStore: MemoryTokenStore(),
      );
      addTearDown(controller.dispose);
      await controller.load('https://ranobelib.me/ru/book/123--novel');
      expect(controller.error, isNull);
      expect(controller.selected, {'1/1', '1/2', '2/1'});
      controller.selectAll(false, volume: '1');
      expect(controller.selected, {'2/1'});
      controller.selectAll(true, volume: '1');
      expect(controller.selected.length, 3);
      await controller.load('https://ranobelib.me/ru/book/123--missing');
      expect(controller.error, isNotNull);
      expect(controller.novel, isNull);
      expect(controller.selected, isEmpty);
      expect(controller.chapterRows, isEmpty);
      expect(controller.volumeKeys, isEmpty);
    },
  );

  test(
    'unavailable chapter fails instead of saving an incomplete book',
    () async {
      final api = RanobeApi(
        client: MockClient((_) async => jsonResponse({'data': {}}, 404)),
      );
      addTearDown(api.close);
      final novel = Novel(
        '123--novel',
        {},
        Chapter.fromResponse([
          rawChapter('1', '1', [1]),
        ]),
      );
      await expectLater(
        BookDownloader(
          api,
        ).download(novel, novel.selectBranch(null), Cancellation(), (_) {}),
        throwsA(isA<ApiException>()),
      );
    },
  );
}

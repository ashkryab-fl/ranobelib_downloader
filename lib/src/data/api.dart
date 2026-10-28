import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/models.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'Загрузка отменена.';
}

class Cancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) throw const DownloadCancelled();
  }

  Future<T> bind<T>(Future<T> future) {
    check();
    return Future.any([
      future,
      _cancelled.future.then<T>((_) => throw const DownloadCancelled()),
    ]);
  }

  Future<void> wait(Duration duration) => bind(Future<void>.delayed(duration));
}

class ApiException implements Exception {
  const ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class RanobeApi {
  RanobeApi({http.Client? client}) : _client = client ?? http.Client();
  static final site = Uri.parse('https://ranobelib.me');
  static const apiHost = 'api.cdnlibs.org';
  final http.Client _client;
  String? token;
  Future<bool> Function()? refreshToken;
  Future<bool> Function()? authorize;
  int _remaining = 90;
  DateTime _windowStart = DateTime.now();

  Map<String, String> _headers(Uri uri) => {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
    'Origin': site.origin,
    'Referer': '${site.origin}/',
    'Site-Id': '3',
    if (uri.host == apiHost && token != null) 'Authorization': 'Bearer $token',
  };

  Future<void> _rateLimit(Cancellation cancel) async {
    final elapsed = DateTime.now().difference(_windowStart);
    final left = const Duration(minutes: 1) - elapsed;
    if (_remaining <= 2 && !left.isNegative) {
      await cancel.wait(left);
      _windowStart = DateTime.now();
      _remaining = 90;
    } else if (_remaining <= 10 && !left.isNegative) {
      await cancel.wait(
        Duration(milliseconds: left.inMilliseconds ~/ _remaining),
      );
    } else if (left.isNegative) {
      _windowStart = DateTime.now();
      _remaining = 90;
    }
  }

  void _updateRate(http.Response response) {
    final remaining = int.tryParse(
      response.headers['x-ratelimit-remaining'] ?? '',
    );
    if (remaining != null) {
      if (remaining > _remaining) _windowStart = DateTime.now();
      _remaining = remaining;
    } else {
      _remaining = (_remaining - 1).clamp(0, 90);
    }
  }

  Future<http.Response> _get(Uri uri, Cancellation cancel) async {
    for (var redirects = 0; redirects < 6; redirects++) {
      if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
        throw const ApiException('Сайт вернул небезопасную ссылку на ресурс.');
      }
      cancel.check();
      final request = http.Request('GET', uri)
        ..headers.addAll(_headers(uri))
        ..followRedirects = false;
      final response = await cancel.bind(
        _client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(const Duration(seconds: 20)),
      );
      cancel.check();
      if (uri.host == apiHost) _updateRate(response);
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) {
          throw const ApiException('Перенаправление без адреса.');
        }
        // Rebuild headers for every host so bearer credentials cannot leak to a CDN.
        uri = uri.resolve(location);
        continue;
      }
      return response;
    }
    throw const ApiException('Слишком много перенаправлений.');
  }

  Future<http.Response> _request(
    Uri uri,
    Cancellation cancel, {
    bool login = true,
  }) async {
    var authAttempted = false;
    const delays = [3, 3, 30, 30];
    for (var attempt = 0; ; attempt++) {
      cancel.check();
      if (uri.host == apiHost) await _rateLimit(cancel);
      try {
        var response = await _get(uri, cancel);
        if (uri.host == apiHost &&
            (response.statusCode == 401 ||
                (response.statusCode == 403 && token == null)) &&
            !authAttempted) {
          authAttempted = true;
          final refreshed =
              refreshToken != null && await cancel.bind(refreshToken!());
          if (!refreshed && login && authorize != null) {
            if (!await cancel.bind(authorize!())) {
              throw const ApiException('Для этой книги нужна авторизация.');
            }
          }
          cancel.check();
          await _rateLimit(cancel);
          response = await _get(uri, cancel);
        }
        if (response.statusCode == 429 || response.statusCode >= 500) {
          if (attempt >= delays.length) {
            throw ApiException(
              'Сервер временно недоступен (HTTP ${response.statusCode}).',
              response.statusCode,
            );
          }
          final retry = int.tryParse(response.headers['retry-after'] ?? '');
          await cancel.wait(
            Duration(seconds: retry?.clamp(1, 120) ?? delays[attempt]),
          );
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ApiException(switch (response.statusCode) {
            401 => 'Сессия истекла. Войдите в свой аккаунт.',
            403 => 'У аккаунта нет доступа к этому содержимому.',
            404 => 'Книга, глава или изображение не найдены.',
            _ => 'Ошибка сайта (HTTP ${response.statusCode}).',
          }, response.statusCode);
        }
        return response;
      } on TimeoutException {
        if (attempt >= delays.length) {
          throw const ApiException(
            'Сервер не отвечает. Проверьте интернет и повторите попытку.',
          );
        }
      } on http.ClientException {
        if (attempt >= delays.length) {
          throw const ApiException(
            'Не удалось соединиться с сайтом. Проверьте интернет.',
          );
        }
      }
      await cancel.wait(Duration(seconds: delays[attempt]));
    }
  }

  Future<Json> getJson(
    Uri uri,
    Cancellation cancel, {
    bool login = true,
  }) async {
    final response = await _request(uri, cancel, login: login);
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException();
      return asMap(decoded);
    } on FormatException {
      throw const ApiException('Сайт вернул некорректный ответ вместо JSON.');
    }
  }

  Future<Novel> loadNovel(String slug, Cancellation cancel) async {
    final info = await getJson(
      Uri.https(apiHost, '/api/manga/$slug', {
        'fields[]': [
          'summary',
          'genres',
          'tags',
          'teams',
          'authors',
          'status_id',
          'artists',
          'format',
          'publisher',
        ],
      }),
      cancel,
    );
    final data = asMap(info['data']);
    if (data.isEmpty) throw const ApiException('Сайт не вернул данные книги.');
    final response = await getJson(
      Uri.https(apiHost, '/api/manga/$slug/chapters'),
      cancel,
    );
    if (response['data'] is! List) {
      throw const ApiException('Сайт не вернул список глав.');
    }
    return Novel(slug, data, Chapter.fromResponse(response['data']));
  }

  Future<Json> chapter(
    String slug,
    ChapterSelection selection,
    Cancellation cancel,
  ) async {
    final data = await getJson(
      Uri.https(apiHost, '/api/manga/$slug/chapter', {
        'volume': selection.chapter.volume,
        'number': selection.chapter.number,
        if (selection.branch.id != '0') 'branch_id': selection.branch.id,
      }),
      cancel,
    );
    final chapter = asMap(data['data']);
    if (chapter['content'] == null || chapter['content'] == '') {
      throw ApiException(
        'Глава ${selection.chapter.number} недоступна или пуста.',
      );
    }
    return chapter;
  }

  Future<Uint8List> image(String url, Cancellation cancel) async {
    final uri = site.resolve(url);
    return (await _request(uri, cancel, login: false)).bodyBytes;
  }

  Future<Json> currentUser({bool login = false}) async {
    final result = await getJson(
      Uri.https(apiHost, '/api/auth/me'),
      Cancellation(),
      login: login,
    );
    final user = asMap(result['data']);
    if (user['id'] == null) {
      throw const ApiException('Не удалось проверить аккаунт.');
    }
    return user;
  }

  Future<Json> exchangeToken(Json payload) async {
    final uri = Uri.https(apiHost, '/api/auth/oauth/token');
    final response = await _client
        .post(
          uri,
          headers: {..._headers(uri), 'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException(
        'Не удалось завершить авторизацию (HTTP ${response.statusCode}).',
        response.statusCode,
      );
    }
    final data = asMap(jsonDecode(response.body));
    if (data['access_token'] is! String ||
        textOf(data['access_token']).isEmpty) {
      throw const ApiException('Сервер не вернул токен авторизации.');
    }
    return data;
  }

  void close() => _client.close();
}

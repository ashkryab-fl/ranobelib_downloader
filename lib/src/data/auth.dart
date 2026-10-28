import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import '../domain/models.dart';

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'ranobelib.oauth';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> delete() => _storage.delete(key: _key);
}

class OAuthRequest {
  OAuthRequest() : verifier = _random(128), state = _random(40);
  final String verifier;
  final String state;
  static const redirect = 'https://ranobelib.me/ru/front/auth/oauth/callback';
  static String _random(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  Uri get url => Uri.https('auth.lib.social', '/auth/oauth/authorize', {
    'scope': '',
    'client_id': '1',
    'response_type': 'code',
    'redirect_uri': redirect,
    'state': state,
    'code_challenge': base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', ''),
    'code_challenge_method': 'S256',
    'prompt': 'consent',
  });
  bool isCallback(Uri uri) {
    final target = Uri.parse(redirect);
    return uri.scheme == target.scheme &&
        uri.host == target.host &&
        uri.port == target.port &&
        uri.path == target.path;
  }

  String codeFromCallback(Uri uri) {
    if (!isCallback(uri) || uri.queryParameters['state'] != state) {
      throw const ApiException(
        'Не удалось проверить ответ авторизации. Попробуйте войти ещё раз.',
      );
    }
    if (uri.queryParameters.containsKey('error')) {
      throw const ApiException('Сайт отклонил авторизацию.');
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const ApiException('В ответе авторизации нет кода.');
    }
    return code;
  }
}

class RanobeAuth {
  RanobeAuth(this.api, {TokenStore? store})
    : store = store ?? SecureTokenStore() {
    api.refreshToken = refresh;
  }
  final RanobeApi api;
  final TokenStore store;
  Json? _tokens;
  Json? user;

  Future<void> restore() async {
    final raw = await store.read();
    if (raw == null) return;
    try {
      _tokens = asMap(jsonDecode(raw));
      final accessToken = _tokens!['access_token'];
      if (accessToken is! String || accessToken.isEmpty) {
        throw const FormatException();
      }
      api.token = accessToken;
      user = await api.currentUser();
    } on FormatException {
      await logout();
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) await logout();
      rethrow;
    }
  }

  Future<void> _save(Json tokens) async {
    await store.write(jsonEncode(tokens));
    _tokens = tokens;
    api.token = textOf(tokens['access_token']);
  }

  Future<void> finish(OAuthRequest request, Uri callback) async {
    final tokens = await api.exchangeToken({
      'grant_type': 'authorization_code',
      'client_id': 1,
      'redirect_uri': OAuthRequest.redirect,
      'code_verifier': request.verifier,
      'code': request.codeFromCallback(callback),
    });
    await _save(tokens);
    user = await api.currentUser();
  }

  Future<void> directToken(String raw) async {
    final token = raw
        .trim()
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .trim();
    if (token.isEmpty) throw const ApiException('Вставьте токен.');
    final previous = api.token;
    final refresh = api.refreshToken;
    api.token = token;
    api.refreshToken = null;
    try {
      final validated = await api.currentUser();
      await _save({'access_token': token});
      user = validated;
    } catch (_) {
      api.token = previous;
      rethrow;
    } finally {
      api.refreshToken = refresh;
    }
  }

  Future<bool> refresh() async {
    final refresh = _tokens?['refresh_token'];
    if (refresh is! String || refresh.isEmpty) return false;
    try {
      final tokens = await api.exchangeToken({
        'grant_type': 'refresh_token',
        'client_id': 1,
        'refresh_token': refresh,
      });
      if (tokens['refresh_token'] == null) tokens['refresh_token'] = refresh;
      await _save(tokens);
      return true;
    } on ApiException catch (e) {
      if (e.status == 400 || e.status == 401) {
        await logout();
        return false;
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    await store.delete();
    _tokens = null;
    user = null;
    api.token = null;
  }
}

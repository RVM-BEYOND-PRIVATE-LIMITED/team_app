import 'dart:convert';
import 'dart:typed_data';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

class _FakeTokens implements TokenStore {
  _FakeTokens(this.token);
  final String? token;
  int unauthorizedCalls = 0;

  @override
  Future<String?> readSchedulerToken() async => token;

  @override
  Future<void> onUnauthorized() async => unauthorizedCalls++;
}

/// Answers every request with a fixed status + body.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body, this.contentType);
  final int status;
  final String body;
  final String contentType;
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    captured = options;
    return ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [contentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

String _jwt(Map<String, dynamic> claims) =>
    'h.${base64Url.encode(utf8.encode(json.encode(claims))).replaceAll('=', '')}.s';

final _now = DateTime.utc(2026, 9, 26, 12);
final _live = _jwt({'userId': 'u1', 'exp': _now.add(const Duration(hours: 10)).millisecondsSinceEpoch ~/ 1000});
final _expired = _jwt({'userId': 'u1', 'exp': _now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000});

Future<(_FakeTokens, _Adapter)> _call(int status, Object? body, {String? token}) async {
  final tokens = _FakeTokens(token ?? _live);
  final adapter = body is String
      ? _Adapter(status, body, 'text/html')
      : _Adapter(status, json.encode(body), 'application/json');
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = adapter
    ..interceptors.add(BearerAuthInterceptor(tokens, clock: () => _now));
  try {
    await dio.get('/x');
  } on DioException catch (_) {}
  return (tokens, adapter);
}

void main() {
  test('attaches the bearer token', () async {
    final (_, adapter) = await _call(200, {'ok': true});
    expect(adapter.captured!.headers['Authorization'], 'Bearer $_live');
  });

  group('signs out when the token is rejected', () {
    test('401 "Please authenticate" (auth guard)', () async {
      final (tokens, _) = await _call(401, {'error': 'Please authenticate'});
      expect(tokens.unauthorizedCalls, 1);
    });

    test('401 "No token provided"', () async {
      final (tokens, _) = await _call(401, {'error': 'No token provided'});
      expect(tokens.unauthorizedCalls, 1);
    });

    test('any 401 once the stored JWT has expired', () async {
      final (tokens, _) = await _call(401, {'error': 'Authentication required with location.'}, token: _expired);
      expect(tokens.unauthorizedCalls, 1);
    });

    test('401 without a Scheduler error body', () async {
      final (tokens, _) = await _call(401, '<html>Unauthorized</html>');
      expect(tokens.unauthorizedCalls, 1);
    });
  });

  group('keeps the session on a controller 401 with a valid token', () {
    for (final msg in [
      'Authentication required with location.', // GET /activities (route has no auth guard)
      'Location context missing.',
      'Invalid password', // POST /users/login
    ]) {
      test('401 "$msg"', () async {
        final (tokens, _) = await _call(401, {'error': msg});
        expect(tokens.unauthorizedCalls, 0);
      });
    }
  });

  test('403 never signs out', () async {
    final (tokens, _) = await _call(403, {'error': 'Access denied. Insufficient privileges.'});
    expect(tokens.unauthorizedCalls, 0);
  });
}

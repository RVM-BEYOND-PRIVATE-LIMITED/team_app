import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

/// What one request looked like when it reached the wire.
class SeenRequest {
  SeenRequest(this.method, this.path, Map<String, dynamic> headers)
      : headers = {
          for (final e in headers.entries) e.key.toLowerCase(): '${e.value}',
        };

  final String method;
  final String path;
  final Map<String, String> headers;

  String? header(String name) => headers[name.toLowerCase()];

  String? get idempotencyKey => header(IdempotencyInterceptor.header);

  String? get bearer {
    final value = header('Authorization');
    return value == null ? null : value.substring('Bearer '.length);
  }
}

/// An HTTP adapter that answers from a script and records every request.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.answer);

  final FutureOr<ResponseBody> Function(RequestOptions options) answer;
  final List<SeenRequest> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(SeenRequest(options.method, options.path, options.headers));
    return answer(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonReply(int status, Object body) => ResponseBody.fromString(
      json.encode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// A JWT-shaped token with [claims]; the signature is never checked here.
String fakeJwt(Map<String, Object?> claims) =>
    'h.${base64Url.encode(utf8.encode(json.encode(claims))).replaceAll('=', '')}.s';

int epochSeconds(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

/// The token store the app's AuthSession implements, in memory.
class FakeTokens implements TokenStore, EssTokenStore {
  FakeTokens({this.schedulerToken, this.refreshToken});

  String? schedulerToken;
  String? refreshToken;
  int unauthorized = 0;

  /// The message each [onUnauthorized] carried, in order.
  final List<String?> messages = [];
  int cleared = 0;

  @override
  Future<String?> readSchedulerToken() async => schedulerToken;

  @override
  Future<void> onUnauthorized({String? message}) async {
    unauthorized++;
    messages.add(message);
    schedulerToken = null;
  }

  @override
  Future<String?> readEssRefreshToken() async => refreshToken;

  @override
  Future<String> installId() async => 'install-1';

  @override
  Future<void> saveEssSession({
    required String accessToken,
    required String refreshToken,
    DateTime? accessExpiresAt,
  }) async {
    schedulerToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearEssSession() async {
    cleared++;
    refreshToken = null;
  }
}

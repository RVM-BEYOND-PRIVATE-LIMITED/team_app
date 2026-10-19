import 'dart:convert';
import 'dart:typed_data';

import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// Replies with a canned status + JSON body (the real Scheduler shapes, from
/// controllers/userController.js login + authSecurityController.js) and
/// captures what the data source put on the wire.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    captured = options;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

(StaffAuthRemoteDataSource, _Adapter) _ds(int status, Map<String, dynamic> body) {
  final adapter = _Adapter(status, body);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))..httpClientAdapter = adapter;
  return (StaffAuthRemoteDataSource(dio), adapter);
}

Future<StaffLoginOutcome> _login(StaffAuthRemoteDataSource ds) =>
    ds.login(username: 'ravi', password: 'secret', locationName: 'Pune');

void main() {
  group('POST /users/login', () {
    test('200 {token,user} → StaffSignedIn; sends username/password/locationName', () async {
      final (ds, adapter) = _ds(200, {
        'token': 'jwt',
        'user': {'userId': 'u1', 'username': 'ravi', 'role': 'hoo', 'locationId': 2, 'locationName': 'Pune'},
      });
      final out = await _login(ds);
      expect(out, isA<StaffSignedIn>());
      final signedIn = out as StaffSignedIn;
      expect(signedIn.token, 'jwt');
      expect(signedIn.identity.role, AppRole.hoo);
      expect(signedIn.identity.locationName, 'Pune');
      expect(adapter.captured!.path, '/users/login');
      expect(adapter.captured!.data, {'username': 'ravi', 'password': 'secret', 'locationName': 'Pune'});
    });

    test('200 two-factor challenge → StaffTwoFactorChallenge (no token)', () async {
      final (ds, _) = _ds(200, {
        'two_factor_required': true,
        'challenge_id': 'c1',
        'sent_to': 'ra***@rvmcad.org',
        'expires_at': '2026-09-26T06:00:00.000Z',
        'location_name': 'Pune',
      });
      final out = await _login(ds);
      expect(out, isA<StaffTwoFactorChallenge>());
      final c = out as StaffTwoFactorChallenge;
      expect(c.challengeId, 'c1');
      expect(c.sentTo, 'ra***@rvmcad.org');
      expect(c.expiresAt, DateTime.utc(2026, 9, 26, 6));
      expect(c.locationName, 'Pune');
    });

    test('200 with neither token nor challenge → ParseFailure, not an "unknown role"', () async {
      final (ds, _) = _ds(200, {'ok': true});
      await expectLater(_login(ds), throwsA(isA<ParseFailure>()));
    });

    test('404 Location not found. → NotFoundFailure with the backend message', () async {
      final (ds, _) = _ds(404, {'error': 'Location not found.'});
      await expectLater(
          _login(ds), throwsA(isA<NotFoundFailure>().having((f) => f.message, 'message', 'Location not found.')));
    });

    test('404 User not found → NotFoundFailure with the backend message', () async {
      final (ds, _) = _ds(404, {'error': 'User not found. Please check your credentials.'});
      await expectLater(_login(ds),
          throwsA(isA<NotFoundFailure>().having((f) => f.message, 'message', contains('User not found'))));
    });

    test('401 Invalid password → UnauthorizedFailure', () async {
      final (ds, _) = _ds(401, {'error': 'Invalid password'});
      await expectLater(_login(ds), throwsA(isA<UnauthorizedFailure>()));
    });

    test('409 ambiguous account → BadResponseFailure with the verbatim message', () async {
      final (ds, _) = _ds(409, {'error': 'More than one account answers to that name.'});
      await expectLater(
          _login(ds),
          throwsA(isA<BadResponseFailure>()
              .having((f) => f.statusCode, 'status', 409)
              .having((f) => f.message, 'message', contains('More than one account'))));
    });

    test('429 limiter → TooManyRequestsFailure keeps the real wait time', () async {
      final (ds, _) = _ds(429, {'error': 'Too many login attempts. Please try again in 15 minutes.'});
      await expectLater(
          _login(ds),
          throwsA(isA<TooManyRequestsFailure>()
              .having((f) => f.message, 'message', contains('15 minutes'))));
    });

    test('503 TWO_FACTOR_UNAVAILABLE → ServerFailure keeps status + code, generic text', () async {
      final (ds, _) = _ds(503, {
        'error': 'Two-factor is on for this account but the code could not be sent: ZEPTOMAIL_API_TOKEN missing',
        'code': 'TWO_FACTOR_UNAVAILABLE',
      });
      await expectLater(
          _login(ds),
          throwsA(isA<ServerFailure>()
              .having((f) => f.statusCode, 'status', 503)
              .having((f) => f.code, 'code', 'TWO_FACTOR_UNAVAILABLE')
              .having((f) => f.message, 'message', isNot(contains('ZEPTOMAIL')))));
    });
  });

  group('POST /users/login/verify', () {
    test('sends challenge_id/code/location_name → StaffSignedIn', () async {
      final (ds, adapter) = _ds(200, {
        'token': 'jwt2',
        'user': {'userId': 'u1', 'username': 'ravi', 'role': 'admin', 'locationId': 2, 'locationName': 'Pune'},
      });
      final out = await ds.verifyTwoFactor(challengeId: 'c1', code: '123456', locationName: 'Pune');
      expect(out.token, 'jwt2');
      expect(out.identity.role, AppRole.admin);
      expect(adapter.captured!.path, '/users/login/verify');
      expect(adapter.captured!.data, {'challenge_id': 'c1', 'code': '123456', 'location_name': 'Pune'});
    });

    test('400 WRONG_CODE → BadResponseFailure with the backend message + code', () async {
      final (ds, _) = _ds(400, {'error': 'That code is not right.', 'code': 'WRONG_CODE'});
      await expectLater(
          ds.verifyTwoFactor(challengeId: 'c1', code: '000000'),
          throwsA(isA<BadResponseFailure>()
              .having((f) => f.message, 'message', 'That code is not right.')
              .having((f) => f.code, 'code', 'WRONG_CODE')));
    });
  });
}

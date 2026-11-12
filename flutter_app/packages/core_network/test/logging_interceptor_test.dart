import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// Runs [body] and returns every line it printed.
Future<List<String>> _printed(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(body,
      zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line)));
  return lines;
}

Dio _dio(HttpClientAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://scheduler.test/api'))
      ..httpClientAdapter = adapter
      ..interceptors.add(LoggingInterceptor());

void main() {
  test('request and response lines carry no number or name', () async {
    final adapter = ScriptedAdapter((_) => jsonReply(200, {'ok': true}));

    final lines = await _printed(() async {
      await _dio(adapter).get<dynamic>('/leads/9999999999',
          queryParameters: {'name': 'Test Student', 'q': '+91 99999 99999'});
    });

    expect(lines, hasLength(2));
    for (final line in lines) {
      expect(line, isNot(contains('9999')));
      expect(line, isNot(contains('Test Student')));
      expect(line, contains('/leads/${Redact.mask}'));
    }
  });

  test('an error line keeps its cause without the number', () async {
    final adapter = ScriptedAdapter((_) => jsonReply(409, {
          'error': 'The number 9999999999 is already on a lead.',
          'code': 'DUPLICATE',
        }));

    final lines = await _printed(() async {
      await expectLater(_dio(adapter).post<dynamic>('/leads', data: {'x': 1}),
          throwsA(isA<DioException>()));
    });

    final error = lines.last;
    expect(error, contains('409'));
    expect(error, contains('is already on a lead'));
    expect(error, isNot(contains('9999999999')));
  });
}

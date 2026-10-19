import 'dart:convert';
import 'dart:io';

import 'package:core_network/core_network.dart';
import 'package:test/test.dart';

void main() {
  group('DohResolver', () {
    late HttpServer server;
    late String endpoint;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      endpoint = 'http://127.0.0.1:${server.port}/dns-query';
      server.listen((request) async {
        request.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({
            'Status': 0,
            'Answer': [
              {'name': request.uri.queryParameters['name'], 'type': 1, 'data': '10.1.2.3'},
            ],
          }));
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('falls back to DoH when the system resolver fails', () async {
      final resolver = DohResolver(endpoint: endpoint);
      final address = await resolver.lookup('no-such-host.invalid');
      expect(address?.address, '10.1.2.3');
    });

    test('uses the system resolver for a real host', () async {
      final resolver = DohResolver(endpoint: endpoint);
      final address = await resolver.lookup('localhost');
      expect(address?.isLoopback, isTrue);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/io.dart';

/// Resolves API hostnames without relying on the device's system resolver.
///
/// Some devices/networks answer NXDOMAIN from the *system* resolver
/// (`SocketException: Failed host lookup …, errno = 7`) for a host that really
/// exists and that a browser loads fine — browsers use their own secure DNS.
/// We try the system resolver first and, only when it fails, fall back to
/// DNS-over-HTTPS addressed by IP: the default endpoint is `1.1.1.1`, so the
/// fallback lookup itself needs no DNS to work.
class DohResolver {
  DohResolver({String? endpoint, HttpClient Function()? client})
        : _endpoint = endpoint ?? defaultEndpoint,
        _client = client ?? HttpClient.new;

  static const defaultEndpoint = 'https://1.1.1.1/dns-query';
  static const _timeout = Duration(seconds: 5);

  final String _endpoint;
  final HttpClient Function() _client;

  /// First address for [host]: system resolver first, DoH as the fallback.
  Future<InternetAddress?> lookup(String host) async {
    try {
      final resolved = await InternetAddress.lookup(host).timeout(_timeout);
      if (resolved.isNotEmpty) return resolved.first;
    } catch (_) {
      // System resolver failed (NXDOMAIN / no network) — try DoH.
    }
    return _lookupOverHttps(host);
  }

  Future<InternetAddress?> _lookupOverHttps(String host) async {
    final client = _client();
    try {
      final uri = Uri.parse('$_endpoint?name=${Uri.encodeQueryComponent(host)}&type=A');
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      return _firstAddress(body);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// First IPv4 answer in a Google/Cloudflare DoH JSON body, or null.
  static InternetAddress? _firstAddress(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map) return null;
    final answers = decoded['Answer'];
    if (answers is! List) return null;
    for (final answer in answers) {
      if (answer is Map && answer['type'] == 1 && answer['data'] is String) {
        return InternetAddress(answer['data'] as String);
      }
    }
    return null;
  }
}

/// A Dio adapter whose [HttpClient] resolves hostnames through [DohResolver],
/// so the app survives a system resolver that cannot see the API hosts.
abstract final class DohHttpClientAdapter {
  static IOHttpClientAdapter create({DohResolver? resolver}) {
    final doh = resolver ?? DohResolver();
    return IOHttpClientAdapter(
      createHttpClient: () => HttpClient()..connectionFactory = _connectVia(doh),
    );
  }

  /// Opens the socket ourselves: resolve with [DohResolver], then connect to the
  /// address.
  ///
  /// `HttpClient` does NOT run TLS over a socket returned from a
  /// `connectionFactory` — it only upgrades on its own default path — so for
  /// `https` we must upgrade the socket here. We secure it with the URL host
  /// (not the resolved IP) so the SNI and certificate check stay correct.
  static Future<ConnectionTask<Socket>> Function(Uri, String?, int?) _connectVia(DohResolver doh) {
    return (url, proxyHost, proxyPort) async {
      final host = proxyHost ?? url.host;
      final port = proxyHost != null ? (proxyPort ?? 80) : url.port;
      final address = await doh.lookup(host);
      if (address == null) {
        throw SocketException(
          "Failed host lookup: '$host'",
          osError: const OSError('No address associated with hostname', 7),
        );
      }
      final task = await Socket.startConnect(address, port);
      if (url.scheme != 'https') return task;
      final tls = task.socket.then((socket) => SecureSocket.secure(socket, host: url.host));
      return ConnectionTask.fromSocket<Socket>(tls, task.cancel);
    };
  }
}

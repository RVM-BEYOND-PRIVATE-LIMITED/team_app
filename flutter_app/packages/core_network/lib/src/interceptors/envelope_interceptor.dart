import 'package:dio/dio.dart';

/// JobPortal wraps every success as `{ "success": true, "data": <payload> }`.
/// The generated models describe only `<payload>`, so we unwrap here — the rest
/// of the app never sees the envelope.
///
/// Binary responses (resume/logo downloads) are passed through untouched.
class EnvelopeInterceptor extends Interceptor {
  const EnvelopeInterceptor();

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final data = response.data;
    if (data is Map && data['success'] == true && data.containsKey('data')) {
      response.data = data['data'];
    }
    handler.next(response);
  }
}

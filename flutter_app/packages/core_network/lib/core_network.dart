/// Shared HTTP layer for both RVM backends, on the provided stack (dio only).
///
/// One centralized [DioFactory] builds both configured Dio instances:
///   * Scheduler (Express)  -> `Authorization: Bearer <jwt>` header
///   * JobPortal (Next.js)  -> `rvm_session` cookie + `{success,data}` envelope
/// Raw dio errors are mapped to typed [Failure]s; [ConnectivityService] confirms
/// real internet (interface up != reachable).
library core_network;

export 'src/api_environment.dart';
export 'src/failure.dart';
export 'src/token_store.dart';
export 'src/ess_token_store.dart';
export 'src/dio_factory.dart';
export 'src/doh_http_client_adapter.dart';
export 'src/connectivity_service.dart';
export 'src/interceptors/bearer_auth_interceptor.dart';
export 'src/interceptors/ess_auth_interceptor.dart';
export 'src/interceptors/envelope_interceptor.dart';
export 'src/interceptors/error_mapping_interceptor.dart';
export 'src/interceptors/logging_interceptor.dart';
export 'src/interceptors/retry_interceptor.dart';

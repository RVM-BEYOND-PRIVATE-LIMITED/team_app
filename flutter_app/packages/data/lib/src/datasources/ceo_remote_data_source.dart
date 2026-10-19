import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// CEO command-centre over the Bearer-JWT Dio (super-admin / executive only —
/// the backend 403s otherwise). Four independent read endpoints.
class CeoRemoteDataSource with DioExecutor {
  CeoRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /ceo/dashboard — snapshot metrics + funnel over [from]..[to].
  Future<CeoDashboard> dashboard({String? from, String? to, String? location}) =>
      guard(() async => Parse.ceoDashboard((await _dio.get('/ceo/dashboard', queryParameters: {
            if (from != null) 'from': from,
            if (to != null) 'to': to,
            if (location != null) 'location': location,
          }))
              .data));

  /// GET /ceo/trends — daily time series over [from]..[to].
  Future<List<CeoTrendPoint>> trends({required String from, required String to, String? location}) =>
      guard(() async => Parse.ceoTrends((await _dio.get('/ceo/trends', queryParameters: {
            'from': from,
            'to': to,
            if (location != null) 'location': location,
          }))
              .data));

  /// GET /ceo/collection-rate-intelligence — receipts vs expected revenue.
  Future<CeoCollectionIntel> collectionRate({String? location, String? method}) =>
      guard(() async =>
          Parse.ceoCollectionIntel((await _dio.get('/ceo/collection-rate-intelligence', queryParameters: {
            if (location != null) 'location': location,
            if (method != null) 'method': method,
          }))
              .data));

  /// GET /ceo/faculty-attendance — yesterday's faculty attendance snapshot.
  Future<CeoFacultyAttendance> facultyAttendance({String? location}) =>
      guard(() async => Parse.ceoFacultyAttendance((await _dio.get('/ceo/faculty-attendance', queryParameters: {
            if (location != null) 'location': location,
          }))
              .data));
}

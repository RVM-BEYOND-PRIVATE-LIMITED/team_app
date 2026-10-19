import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Public (unauthenticated) endpoints over the JobPortal Dio — companies browse.
class PublicRemoteDataSource with DioExecutor {
  PublicRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<Company>> companies({String? search, String? industry, int page = 1}) =>
      guard(() async {
        final r = await _dio.get('/public/companies', queryParameters: {
          'page': page,
          if (search != null && search.isNotEmpty) 'search': search,
          if (industry != null && industry.isNotEmpty) 'industry': industry,
        });
        return Parse.companies(r.data);
      });

  Future<Company> company(String id) =>
      guard(() async => Parse.company(asMap((await _dio.get('/public/companies/$id')).data)));

  Future<List<JobSummary>> companyJobs(String id, {int page = 1}) => guard(() async =>
      Parse.jobList((await _dio.get('/public/companies/$id/jobs', queryParameters: {'page': page})).data));

  /// Live promotional offer, or null when none is running.
  Future<Offer?> activeOffer() =>
      guard(() async => Parse.activeOffer((await _dio.get('/public/active-offer')).data));

  // ── Registration reference data ──────────────────────────────────────────
  /// Industry → Domain → Role → Skills taxonomy for the registration pickers.
  Future<List<TaxonomyIndustry>> taxonomy() =>
      guard(() async => Parse.taxonomy((await _dio.get('/public/taxonomy')).data));

  /// Indian states (name + ISO code) for the location picker.
  Future<List<IndiaState>> states() =>
      guard(() async => Parse.indiaStates((await _dio.get('/public/locations')).data));

  /// Cities of a state (by ISO [stateCode]) for the location picker.
  Future<List<String>> cities(String stateCode) => guard(() async => Parse.cityNames(
      (await _dio.get('/public/locations', queryParameters: {'state': stateCode})).data));

  /// Submit a ban appeal (public — reachable while a candidate is banned).
  /// Returns the reference id. 429 surfaces as TooManyRequestsFailure.
  Future<String> submitBanAppeal({
    required String name,
    required String email,
    required String phone,
    required String message,
  }) =>
      guard(() async {
        final r = await _dio.post('/support/ban-appeals', data: {
          'name': name,
          'email': email,
          'phone': phone,
          'message': message,
        });
        return asMap(r.data)['reference_id']?.toString() ?? '';
      });
}

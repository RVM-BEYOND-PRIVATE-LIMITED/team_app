import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/public_remote_data_source.dart';
import 'connectivity_guard.dart';

class PublicRepository with ConnectivityGuard {
  PublicRepository({required PublicRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final PublicRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<Company>> companies({String? search, String? industry, int page = 1}) async {
    await ensureOnline();
    return _remote.companies(search: search, industry: industry, page: page);
  }

  Future<Company> company(String id) async {
    await ensureOnline();
    return _remote.company(id);
  }

  Future<List<JobSummary>> companyJobs(String id, {int page = 1}) async {
    await ensureOnline();
    return _remote.companyJobs(id, page: page);
  }

  Future<Offer?> activeOffer() async {
    await ensureOnline();
    return _remote.activeOffer();
  }

  Future<List<TaxonomyIndustry>> taxonomy() async {
    await ensureOnline();
    return _remote.taxonomy();
  }

  Future<List<IndiaState>> states() async {
    await ensureOnline();
    return _remote.states();
  }

  Future<List<String>> cities(String stateCode) async {
    await ensureOnline();
    return _remote.cities(stateCode);
  }

  Future<String> submitBanAppeal({
    required String name,
    required String email,
    required String phone,
    required String message,
  }) async {
    await ensureOnline();
    return _remote.submitBanAppeal(name: name, email: email, phone: phone, message: message);
  }
}

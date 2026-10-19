import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/feedback_remote_data_source.dart';
import 'connectivity_guard.dart';

/// App feedback (JobPortal).
class FeedbackRepository with ConnectivityGuard {
  FeedbackRepository({required FeedbackRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final FeedbackRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<String> submit(FeedbackDraft draft) async {
    await ensureOnline();
    return _remote.submit(draft);
  }

  Future<String> uploadScreenshot(List<int> bytes, String filename) async {
    await ensureOnline();
    return _remote.uploadScreenshot(bytes, filename);
  }

  Future<List<FeedbackItem>> myFeedback({int page = 1}) async {
    await ensureOnline();
    return _remote.myFeedback(page: page);
  }
}

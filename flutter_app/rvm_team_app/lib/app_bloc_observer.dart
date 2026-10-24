import 'package:core_network/core_network.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_crash.dart';
import 'app_feedback.dart';

/// Last line of defence for an event handler that throws something a screen did
/// not catch. A typed [Failure] keeps the backend's own wording; anything else
/// gets the generic line, because the raw exception is for the log, not staff.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    final message =
        error is Failure ? error.message : 'Something went wrong. Please try again.';
    CrashReporter.record(error, stackTrace,
        reason: 'bloc:${bloc.runtimeType}');
    CrashReporter.note('last_user_message', message);
    showAppMessage(message);
  }
}

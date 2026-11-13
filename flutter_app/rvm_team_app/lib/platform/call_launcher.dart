import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:url_launcher/url_launcher.dart';

/// A module's start-call request (team_app #50, item 1). It asks that module's
/// server to start a call and completes with the number to dial, or throws a
/// typed [Failure] the way a repository call does. Each module passes its own,
/// for example `() => repository.startCall(leadId)`, once its route exists.
typedef StartCallRequest = Future<String> Function();

/// Hands [uri] to another app on the phone. True when one took it.
typedef ExternalLaunch = Future<bool> Function(Uri uri);

/// The real [ExternalLaunch]: url_launcher in external-application mode.
///
/// On Android this sends `ACTION_VIEW` for the `tel:` URI, which the system
/// answers as it does `ACTION_DIAL`: the phone's dialer opens with the number
/// filled in and not dialled. Neither needs a permission; only `ACTION_CALL`
/// does (`CALL_PHONE`), and the app never asks for it.
///
/// `canLaunchUrl` is not used: the Android plugin's debug build writes the
/// URL it checks to logcat, and that URL holds the number. When no app takes
/// the URI, the Android plugin throws a `PlatformException` whose message holds
/// the URL too; [CallLauncher] drops it unread.
Future<bool> launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens the phone's dialer for a module's call (team_app #50, item 1).
///
/// It runs the module's start-call request, checks the number it returns and
/// hands `tel:<number>` to the dialer. The number lives only in a local
/// variable between the reply and the hand-off: it is never shown, stored,
/// logged, put in a result, an exception or a crash report. Every outcome is a
/// [CallLaunchResult] whose message a screen can show as it is.
class CallLauncher {
  const CallLauncher({ExternalLaunch launch = launchExternally})
      : _launch = launch;

  final ExternalLaunch _launch;

  /// One optional leading `+`, then 1 to 15 ASCII digits (15 is E.164's
  /// ceiling). Space around the number is trimmed; spaces, dashes, brackets
  /// and letters inside it are refused, not cleaned.
  static final _dialable = RegExp(r'^\+?[0-9]{1,15}$');

  /// Runs [startCall] and opens the dialer with the number it returns.
  /// Never throws: a refused request, a number that cannot be dialled and a
  /// dialer that does not open each come back as a [CallLaunchFailure].
  Future<CallLaunchResult> dial(StartCallRequest startCall) async {
    final String number;
    try {
      number = (await startCall()).trim();
    } on Failure catch (failure) {
      return CallStartFailed(_withoutNumbers(failure));
    } on DioException catch (e) {
      return CallStartFailed(_withoutNumbers(Failure.fromDio(e)));
    } on FormatException {
      return const CallStartFailed(ParseFailure());
    } on TypeError {
      return const CallStartFailed(ParseFailure());
    } catch (_) {
      // Anything else may quote the reply in its text, so it is dropped unread.
      return const CallStartFailed(UnknownFailure());
    }

    if (!_dialable.hasMatch(number)) return const CallNumberInvalid();

    try {
      final opened = await _launch(Uri(scheme: 'tel', path: number));
      return opened ? const CallDialerOpened() : const CallDialerUnavailable();
    } catch (_) {
      // url_launcher's PlatformException names the URL, and with it the
      // number, so it is dropped unread.
      return const CallDialerUnavailable();
    }
  }

  /// [failure], or the same kind of failure rebuilt without a phone-like
  /// number, in case a server wrote one into its error text (team_app #61).
  /// The app's own failure messages carry none, so they come back as they are.
  static Failure _withoutNumbers(Failure failure) {
    // Redact.text masks runs of 10+ digits; a dialable number can be shorter
    // (e.g. a landline), so any run of 6+ digits, spaces, dots, dashes or
    // brackets between them included, is masked too.
    final message = Redact.text(failure.message)
        .replaceAll(_shortNumber, Redact.mask);
    if (message == failure.message) return failure;
    final status = failure.statusCode;
    if (status != null) {
      return Failure.fromStatus(
          status, message, failure.code, failure.requestId);
    }
    // No status: keep the failure's kind where it can carry server text.
    if (failure is BadResponseFailure) {
      return BadResponseFailure(message,
          code: failure.code, requestId: failure.requestId);
    }
    return UnknownFailure(message);
  }

  static final RegExp _shortNumber = RegExp(r'\+?\d(?:[\s.\-()]*\d){5,}');
}

/// What [CallLauncher.dial] did. None of these carries the number.
sealed class CallLaunchResult extends Equatable {
  const CallLaunchResult();

  /// The line a screen shows for this outcome.
  String get message;

  @override
  List<Object?> get props => [];

  @override
  String toString() => '$runtimeType: $message';
}

/// The dialer opened with the number filled in.
final class CallDialerOpened extends CallLaunchResult {
  const CallDialerOpened();

  @override
  String get message => 'Phone app opened.';
}

/// The call could not be handed to the dialer. [message] states why.
sealed class CallLaunchFailure extends CallLaunchResult {
  const CallLaunchFailure();
}

/// The module's start-call request was refused or failed: offline, timed out,
/// the session ended, the module is off and so on. [failure] keeps its type,
/// status and code, so a screen can react as it does to any other [Failure].
final class CallStartFailed extends CallLaunchFailure {
  const CallStartFailed(this.failure);

  /// The request's failure. Any phone-like number a server wrote into its
  /// message has been taken out already.
  final Failure failure;

  @override
  String get message => failure.message;

  @override
  List<Object?> get props => [failure];

  @override
  String toString() => 'CallStartFailed: $failure';
}

/// The reply's number is not a dialable phone number.
final class CallNumberInvalid extends CallLaunchFailure {
  const CallNumberInvalid();

  @override
  String get message => 'This number cannot be dialled from the app.';
}

/// No app on the phone took the call: there is no dialer (a tablet without
/// telephony, for example), or the hand-off failed.
final class CallDialerUnavailable extends CallLaunchFailure {
  const CallDialerUnavailable();

  @override
  String get message => 'No phone app on this device could open the call.';
}

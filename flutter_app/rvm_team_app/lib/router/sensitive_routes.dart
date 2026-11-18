import 'module_routes.dart';

/// Switches the class roster's screenshot block on (team_app #52 item 1). Off
/// unless a build passes `--dart-define=SECURE_ROSTER=true`: the roster is
/// every faculty member's daily screen, so the block reaches them only when
/// the owner turns it on (the issue's rules: new behaviour ships switched off).
const bool secureRosterOn =
    bool.fromEnvironment('SECURE_ROSTER', defaultValue: false);

/// The class roster, `/work/batch/:id/mark`: student names and the fee-hold
/// flag. Class marking stays outside the punched-in rule, but the roster is
/// screenshot-blocked (team_app #52, question 3's default) once its switch
/// ([secureRosterOn]) is on.
final _roster = RegExp(r'^/work/batch/[^/]+/mark$');

/// True when the screen at [location] must stay off screenshots, the
/// app-switcher preview and screen recordings (team_app #52, item 1): every
/// route of a module marked [TeamModule.sensitive], and the class roster while
/// [roster] is on ([secureRosterOn] unless a caller says otherwise). Home, the
/// Wall and every other screen are not.
bool isSensitiveLocation(String location, {bool roster = secureRosterOn}) =>
    (moduleForLocation(location)?.sensitive ?? false) ||
    (roster && _roster.hasMatch(location));

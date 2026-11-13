import 'module_routes.dart';

/// The class roster, `/work/batch/:id/mark`: student names and the fee-hold
/// flag. Class marking stays outside the punched-in rule, but the roster is
/// screenshot-blocked (team_app #52, question 3's default).
final _roster = RegExp(r'^/work/batch/[^/]+/mark$');

/// True when the screen at [location] must stay off screenshots, the
/// app-switcher preview and screen recordings (team_app #52, item 1): every
/// route of a module marked [TeamModule.sensitive], and the class roster.
/// Home, the Wall and every other screen are not.
bool isSensitiveLocation(String location) =>
    (moduleForLocation(location)?.sensitive ?? false) ||
    _roster.hasMatch(location);

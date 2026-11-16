import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that intentionally keep a literal colour:
///  * the ironwood/forge brand band and the white content drawn on it;
///  * the fixed-dark image cropper;
///  * medal/celebration artwork that is the same in both themes;
///  * the notification small-icon tint and the TEST SERVER ribbon.
///
/// Every other file must use `context.palette` or `ColorScheme`.
const _allowList = {
  'lib/app_feedback.dart',
  'lib/features/attendance/punch_screen.dart',
  'lib/features/auth/splash_screen.dart',
  'lib/features/fees/outcome/outcome_sheet.dart',
  'lib/features/home/home_screen.dart',
  'lib/features/me/bank_details_screen.dart',
  'lib/features/me/id_card_screen.dart',
  'lib/features/me/profile_screen.dart',
  'lib/features/requests/approvals_screen.dart',
  'lib/features/requests/requests_screen.dart',
  'lib/features/shell/team_shell.dart',
  'lib/features/wall/wall_widgets.dart',
  'lib/main.dart',
  'lib/push/push_service.dart',
  'lib/widgets/badge_kit.dart',
  'lib/widgets/env_ribbon.dart',
  'lib/widgets/image_crop_screen.dart',
  'lib/widgets/team_header.dart',
  'lib/widgets/team_kit.dart',
};

final _rawColour = RegExp(r'RvmColors\.|Color\(0x|\bColors\.');
final _allowedToken = RegExp(
    r'RvmColors\.(ironwood|ironwoodEnd|white|clay)|Colors\.(transparent|white|black|white54)');

void main() {
  test('no raw colours outside the palette allow-list', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue, reason: 'run from rvm_team_app');
    final offenders = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (_allowList.contains(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!_rawColour.hasMatch(line)) continue;
        if (_allowedToken.hasMatch(line) &&
            !line.contains('Color(0x') &&
            !line.contains('Colors.grey') &&
            !line.contains('Colors.red') &&
            !line.contains('Colors.green')) {
          continue;
        }
        offenders.add('$path:${i + 1}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use context.palette or ColorScheme:\n${offenders.join('\n')}');
  });
}

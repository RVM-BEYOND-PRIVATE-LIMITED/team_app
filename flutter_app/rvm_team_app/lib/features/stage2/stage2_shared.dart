import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../data/repositories/team_stage2_repository.dart';
import '../../widgets/blocked_state.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';

TeamStage2Repository? stage2RepositoryOrNull() {
  final getIt = GetIt.instance;
  return getIt.isRegistered<TeamStage2Repository>()
      ? getIt<TeamStage2Repository>()
      : null;
}

TeamStage2Repository stage2Repository() {
  final repo = stage2RepositoryOrNull();
  if (repo == null) throw StateError('Stage 2 repository is not registered.');
  return repo;
}

Widget stage2Failure(Failure? failure, {required VoidCallback onRetry}) {
  final blocked = blockedReasonFor(failure);
  if (blocked != null) {
    return BlockedState(
        reason: blocked,
        message: failure?.message,
        actionLabel: 'Try again',
        onAction: onRetry);
  }
  return AppError(
      message: failure?.message ?? 'Could not load this screen.',
      onRetry: onRetry);
}

String stage2Date(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String stage2DateTime(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '${stage2Date(local)} $h:${local.minute.toString().padLeft(2, '0')} '
      '${local.hour < 12 ? 'AM' : 'PM'}';
}

String stage2Day(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

Future<DateTime?> pickStage2Date(BuildContext context, DateTime initial,
    {DateTime? first}) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first ?? DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 730)),
  );
  return date;
}

Widget stage2Empty(String message) =>
    AppEmpty(message: message, icon: Icons.inbox_outlined);

class Stage2Section extends StatelessWidget {
  const Stage2Section(
      {super.key, required this.title, required this.children, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: RvmSpacing.sm),
          child: Row(
            children: [
              Expanded(
                  child: TeamSectionHeader(title: title, trailing: trailing)),
            ],
          ),
        ),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: RvmSpacing.sm),
          children[i],
        ],
      ],
    );
  }
}

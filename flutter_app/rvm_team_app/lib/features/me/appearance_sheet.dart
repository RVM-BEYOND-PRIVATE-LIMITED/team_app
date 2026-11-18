import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../theme/theme_cubit.dart';
import '../../theme/theme_preference.dart';

/// RVM's dialog rule: a sheet closes only with its own control, never by
/// tapping outside or dragging.
Future<void> showAppearanceSheet(BuildContext context) {
  final cubit = context.read<ThemeCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: const AppearanceSheet(),
    ),
  );
}

class AppearanceSheet extends StatelessWidget {
  const AppearanceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ThemeCubit>().state;
    final p = context.palette;
    return PopScope(
      canPop: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: RvmSpacing.sm),
              RadioGroup<ThemeChoice>(
                groupValue: state.open ? state.choice : ThemeChoice.light,
                onChanged: (choice) {
                  if (choice != null) {
                    context.read<ThemeCubit>().select(choice);
                  }
                },
                child: Column(
                  children: [
                    for (final choice in ThemeChoice.values)
                      RadioListTile<ThemeChoice>(
                        value: choice,
                        contentPadding: EdgeInsets.zero,
                        activeColor: p.primary,
                        title: Text(choice.label),
                        subtitle: Text(choice.subtitle),
                      ),
                  ],
                ),
              ),
              if (!state.open)
                Padding(
                  padding: const EdgeInsets.only(top: RvmSpacing.sm),
                  child: Text(
                    'Custom appearance is not open for your account yet.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: p.muted),
                  ),
                ),
              if (state.pendingSave)
                Padding(
                  padding: const EdgeInsets.only(top: RvmSpacing.sm),
                  child: Text(
                    'Your choice is kept on this phone and will be saved '
                    'when the connection is back.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: p.muted),
                  ),
                ),
              const SizedBox(height: RvmSpacing.lg),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

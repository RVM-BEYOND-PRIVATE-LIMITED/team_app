import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// Phase 2C, E7: the digital staff ID card with its signed verification link.
class IdCardScreen extends StatefulWidget {
  const IdCardScreen({super.key});

  @override
  State<IdCardScreen> createState() => _IdCardScreenState();
}

class _IdCardScreenState extends State<IdCardScreen> {
  bool _loading = true;
  Failure? _failure;
  IdCard? _card;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final card = await getIt<EssRepository>().myIdCard();
      if (!mounted) return;
      setState(() {
        _card = card;
        _loading = false;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _failure = f;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const TeamPageHeader(title: 'ID card', subtitle: Text('Your employee card')),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) return AppError(message: _failure!.message, onRetry: _load);
    final card = _card!;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        Card(
          child: Container(
            padding: const EdgeInsets.all(RvmSpacing.lg),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [RvmColors.ironwood, Color(0xFF52201A)]),
              borderRadius: BorderRadius.circular(RvmRadii.lg),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: RvmColors.ivory,
                  backgroundImage: (card.photoUrl != null && card.photoUrl!.isNotEmpty) ? NetworkImage(card.photoUrl!) : null,
                  child: (card.photoUrl == null || card.photoUrl!.isEmpty)
                      ? Text(card.fullName.isEmpty ? '?' : card.fullName.substring(0, 1).toUpperCase(),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: RvmColors.ironwood))
                      : null,
                ),
                const SizedBox(height: RvmSpacing.md),
                Text(card.fullName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: RvmColors.ivory, fontWeight: FontWeight.w700)),
                if (card.designation != null)
                  Text(card.designation!, style: TextStyle(color: RvmColors.ivory.withValues(alpha: 0.85))),
                if (card.employeeCode != null) ...[
                  const SizedBox(height: 4),
                  Text('Employee ${card.employeeCode}', style: TextStyle(color: RvmColors.ivory.withValues(alpha: 0.75))),
                ],
                const SizedBox(height: 8),
                Text([card.departmentName, card.branchName].where((s) => s != null && s.isNotEmpty).join(' · '),
                    textAlign: TextAlign.center, style: TextStyle(color: RvmColors.ivory.withValues(alpha: 0.75))),
                const SizedBox(height: 8),
                Text('ACTIVE EMPLOYEE', style: TextStyle(color: RvmColors.teamSeed, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ],
            ),
          ),
        ),
        if (card.verifyUrl != null) ...[
          const SizedBox(height: RvmSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(RvmSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Verification link', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  SelectableText(card.verifyUrl!, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: card.verifyUrl!));
                      messenger..hideCurrentSnackBar()..showSnackBar(const SnackBar(content: Text('Link copied.')));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy link'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: RvmSpacing.md),
        Text('The link proves employment without a sign-in and expires in 90 days.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

import 'dart:convert';

import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import 'bloc/account_action_bloc.dart';

/// Account & security for the signed-in person — the existing `/api/me/*`
/// endpoints behind the web Settings page.
class AccountSecurityScreen extends StatelessWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<MeBloc>()..add(const LoadRequested()),
      child: const _SecurityView(),
    );
  }
}

class _SecurityView extends StatelessWidget {
  const _SecurityView();

  @override
  Widget build(BuildContext context) {
    return TeamScaffold(
      title: 'Account & Security',
      body: BlocBuilder<MeBloc, LoadState<TeamProfile>>(
        builder: (context, state) {
          return switch (state.status) {
            LoadStatus.loading || LoadStatus.initial => const AppLoading(),
            LoadStatus.failure => AppError(
                message:
                    state.failure?.message ?? 'Could not load your account.',
                onRetry: () =>
                    context.read<MeBloc>().add(const LoadRefreshed()),
              ),
            _ => _body(context, state.data!),
          };
        },
      ),
    );
  }

  Widget _body(BuildContext context, TeamProfile p) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const TeamSectionHeader(
            title: 'Sign-in details', caption: 'Kept private to you'),
        const SizedBox(height: 8),
        _InfoCard(rows: [
          (
            'Email',
            p.email ?? 'Not set',
            p.emailVerified ? 'Verified' : 'Unverified'
          ),
          ('Phone', p.phoneNumber ?? 'Not set', null),
          ('Two-factor', p.twoFactorEnabled ? 'On' : 'Off', null),
        ]),
        const SizedBox(height: RvmSpacing.lg),
        const TeamSectionHeader(
            title: 'Security Center', caption: 'Credentials & sessions'),
        const SizedBox(height: 8),
        TeamCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Change photo'),
                subtitle: const Text('JPEG or PNG, up to 5 MB'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _changePhoto(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('Change password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _changePassword(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: const Text('Change email'),
                subtitle:
                    const Text('Confirmed with a code to the new address'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _changeEmail(context, p),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.smartphone),
                title: const Text('Change phone number'),
                subtitle: const Text('Confirmed with an SMS code'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _changePhone(context, p),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.verified_user_outlined),
                title: const Text('Two-factor sign-in'),
                subtitle: Text(p.twoFactorEnabled
                    ? 'On — a code is emailed at sign-in'
                    : 'Off'),
                value: p.twoFactorEnabled,
                onChanged: (v) =>
                    v ? _enableTwoFactor(context) : _disableTwoFactor(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: RvmSpacing.lg),
        Center(
          child: Text(
              'Attendance-only logins change password here; email and phone go through HR.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }

  // ── actions ──────────────────────────────────────────────────────────

  void _changePassword(BuildContext context) {
    final screen = context;
    _showActionDialog(
      context,
      build: (close, bloc) => _ChangePasswordForm(
        bloc: bloc,
        close: close,
        onEmail: () {
          close();
          final p = screen.read<MeBloc>().state.data;
          if (p != null) _changeEmail(screen, p);
        },
        onTwoFactor: () {
          close();
          final p = screen.read<MeBloc>().state.data;
          if (p == null) return;
          if (p.twoFactorEnabled) {
            _disableTwoFactor(screen);
          } else {
            _enableTwoFactor(screen);
          }
        },
      ),
    );
  }

  Future<void> _changePhoto(BuildContext context) async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !context.mounted) return;
    // E10: the ESS path works for attendance-only staff too; the Scheduler upload is the
    // fallback for portal logins (e.g. an unsupported image type on the ESS).
    final contentType = switch (file.extension?.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (contentType != null) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await getIt<EssRepository>()
            .putMyPhoto(base64: base64Encode(bytes), contentType: contentType);
        if (context.mounted) context.read<MeBloc>().add(const LoadRefreshed());
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Photo updated.')));
        return;
      } on Failure {
        // Fall through to the Scheduler upload.
      }
    }
    if (!context.mounted) return;
    await _runAccountAction(
        context, AccountUploadPhoto(bytes: bytes, filename: file.name));
  }

  void _changeEmail(BuildContext context, TeamProfile p) => _showActionDialog(
        context,
        build: (close, bloc) =>
            _ChangeEmailFlow(bloc: bloc, close: close, current: p.email),
      );

  void _changePhone(BuildContext context, TeamProfile p) => _showActionDialog(
        context,
        build: (close, bloc) =>
            _ChangePhoneFlow(bloc: bloc, close: close, current: p.phoneNumber),
      );

  void _enableTwoFactor(BuildContext context) => _showActionDialog(
        context,
        build: (close, bloc) => _EnableTwoFactorFlow(bloc: bloc, close: close),
      );

  void _disableTwoFactor(BuildContext context) => _showActionDialog(
        context,
        build: (close, bloc) => _DisableTwoFactorForm(bloc: bloc, close: close),
      );

  /// Runs a one-shot action with no dialog (e.g. photo upload), then refreshes
  /// the profile and reports the real outcome.
  Future<void> _runAccountAction(
      BuildContext context, AccountActionEvent event) async {
    final me = context.read<MeBloc>();
    final bloc = getIt<AccountActionBloc>()..add(event);
    try {
      final state = await bloc.stream.firstWhere(
        (s) =>
            s.status == WriteStatus.success || s.status == WriteStatus.failure,
      );
      if (state.status == WriteStatus.success) {
        me.add(const LoadRefreshed());
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.message ?? 'Done.')));
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(state.error ?? 'Could not complete that.')));
      }
    } finally {
      await bloc.close();
    }
  }

  void _showActionDialog(BuildContext context,
      {required Widget Function(VoidCallback close, AccountActionBloc bloc)
          build}) {
    final me = context.read<MeBloc>();
    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider(
        create: (_) => getIt<AccountActionBloc>(),
        child: BlocListener<AccountActionBloc, AccountActionState>(
          listenWhen: (a, b) => a.status != b.status,
          listener: (context, state) {
            if (state.status == WriteStatus.success) {
              me.add(const LoadRefreshed());
            }
          },
          child: Builder(
            builder: (ctx) => build(
                () => Navigator.of(ctx).pop(), ctx.read<AccountActionBloc>()),
          ),
        ),
      ),
    );
  }
}

// ── shared form scaffolding ───────────────────────────────────────────────

class _ActionDialog extends StatelessWidget {
  const _ActionDialog(
      {required this.title, required this.children, required this.bloc});
  final String title;
  final List<Widget> children;
  final AccountActionBloc bloc;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AccountActionBloc, AccountActionState>(
      bloc: bloc,
      builder: (context, state) {
        return AlertDialog(
          title: Row(
            children: [
              const TeamIconBadge(
                  icon: Icons.shield_outlined, size: 34, iconSize: 17),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontSize: 17))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...children,
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: RvmSpacing.sm),
                    child: Text(state.error!,
                        style: const TextStyle(
                            color: RvmColors.danger, fontSize: 12)),
                  ),
                if (state.status == WriteStatus.submitting)
                  const Padding(
                      padding: EdgeInsets.only(top: RvmSpacing.sm),
                      child: LinearProgressIndicator()),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChangePasswordForm extends StatefulWidget {
  const _ChangePasswordForm({
    required this.bloc,
    required this.close,
    required this.onEmail,
    required this.onTwoFactor,
  });
  final AccountActionBloc bloc;
  final VoidCallback close;
  final VoidCallback onEmail;
  final VoidCallback onTwoFactor;
  @override
  State<_ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<_ChangePasswordForm> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  int get _strength {
    final value = _new.text;
    var score = 0;
    if (value.length >= 8) score++;
    if (value.contains(RegExp(r'[A-Z]'))) score++;
    if (value.contains(RegExp(r'[0-9!@#\$%^&*(),.?":{}|<>]'))) score++;
    if (value.length >= 12) score++;
    return score;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return BlocConsumer<AccountActionBloc, AccountActionState>(
      bloc: widget.bloc,
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == WriteStatus.success) {
          widget.close();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Password changed.')));
        }
      },
      builder: (context, s) {
        final strong = _strength >= 3;
        return _ActionDialog(
            title: 'Security Center',
            bloc: widget.bloc,
            children: [
              TeamSegmentedTabs(
                labels: const ['Password', 'Email', '2-Factor'],
                selectedIndex: 0,
                onChanged: (i) {
                  if (i == 1) widget.onEmail();
                  if (i == 2) widget.onTwoFactor();
                },
              ),
              const SizedBox(height: 12),
              const TeamNotice(
                icon: Icons.error_outline_rounded,
                tone: TeamPillTone.warning,
                text:
                    'For your safety, re-enter your current password to authorize credential modifications.',
              ),
              const SizedBox(height: 12),
              Text('Current password',
                  style: text.labelMedium
                      ?.copyWith(fontSize: 11, color: RvmColors.ink)),
              const SizedBox(height: 5),
              TextField(
                controller: _old,
                obscureText: _obscureOld,
                decoration: InputDecoration(
                  hintText: '••••••••••••',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscureOld = !_obscureOld),
                    icon: Icon(
                        _obscureOld
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('New password',
                      style: text.labelMedium
                          ?.copyWith(fontSize: 11, color: RvmColors.ink)),
                  const SizedBox(width: 4),
                  Text('(min. 8 chars)',
                      style: text.bodySmall
                          ?.copyWith(fontSize: 9, color: RvmColors.subtle)),
                ],
              ),
              const SizedBox(height: 5),
              TextField(
                controller: _new,
                obscureText: _obscureNew,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '••••••••••',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    icon: Icon(
                        _obscureNew
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: i < _strength
                              ? RvmColors.success
                              : RvmColors.sand,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    if (i < 3) const SizedBox(width: 4),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    _strength >= 3
                        ? 'Strong'
                        : (_strength == 2 ? 'Good' : 'Weak'),
                    style: text.labelSmall?.copyWith(
                      fontSize: 9,
                      color: _strength >= 3
                          ? RvmColors.success
                          : RvmColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _rule(context, _new.text.length >= 8, '8+ chars'),
                  const SizedBox(width: 10),
                  _rule(context, _new.text.contains(RegExp(r'[A-Z]')),
                      'Uppercase'),
                  const SizedBox(width: 10),
                  _rule(context, _new.text.contains(RegExp(r'[0-9!@#\$%^&*]')),
                      'Symbol/digit'),
                ],
              ),
              const SizedBox(height: 10),
              Text('Confirm new password',
                  style: text.labelMedium
                      ?.copyWith(fontSize: 11, color: RvmColors.ink)),
              const SizedBox(height: 5),
              TextField(
                controller: _confirm,
                obscureText: _obscureConfirm,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '••••••••••',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.shield_outlined,
                      size: 13, color: RvmColors.subtle),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                        'All active sessions except this will be logged out.',
                        style: text.bodySmall
                            ?.copyWith(fontSize: 9, color: RvmColors.subtle)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.close,
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42)),
                      child:
                          const Text('Cancel', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: s.status == WriteStatus.submitting || !strong
                          ? null
                          : () {
                              if (_new.text.length < 8) return;
                              if (_confirm.text != _new.text) {
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(const SnackBar(
                                      content:
                                          Text('Passwords do not match.')));
                                return;
                              }
                              widget.bloc.add(AccountChangePassword(
                                  oldPassword: _old.text,
                                  newPassword: _new.text));
                            },
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(42)),
                      child: const Text('Update Password',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ]);
      },
    );
  }

  Widget _rule(BuildContext context, bool ok, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ok ? Icons.check_rounded : Icons.circle_outlined,
            size: 10, color: ok ? RvmColors.success : RvmColors.subtle),
        const SizedBox(width: 3),
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 8.5,
                  color: ok ? RvmColors.success : RvmColors.subtle,
                  fontWeight: FontWeight.w600,
                )),
      ],
    );
  }
}

class _ChangeEmailFlow extends StatefulWidget {
  const _ChangeEmailFlow(
      {required this.bloc, required this.close, this.current});
  final AccountActionBloc bloc;
  final VoidCallback close;
  final String? current;
  @override
  State<_ChangeEmailFlow> createState() => _ChangeEmailFlowState();
}

class _ChangeEmailFlowState extends State<_ChangeEmailFlow> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AccountActionBloc, AccountActionState>(
      bloc: widget.bloc,
      listenWhen: (a, b) => a.status != b.status || a.codeSent != b.codeSent,
      listener: (context, s) {
        if (s.codeSent) setState(() => _sent = true);
        if (s.status == WriteStatus.success && !s.codeSent) {
          widget.close();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Email updated.')));
        }
      },
      builder: (context, s) => _ActionDialog(
        title: _sent ? 'Confirm new email' : 'Change email',
        bloc: widget.bloc,
        children: _sent
            ? [
                Text('Enter the 6-digit code sent to ${_email.text.trim()}.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: RvmSpacing.sm),
                TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '6-digit code')),
                const SizedBox(height: RvmSpacing.md),
                FilledButton(
                  onPressed: s.status == WriteStatus.submitting
                      ? null
                      : () => widget.bloc
                          .add(AccountConfirmEmail(_code.text.trim())),
                  child: const Text('Confirm'),
                ),
              ]
            : [
                if (widget.current != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Current: ${widget.current}',
                          style: Theme.of(context).textTheme.bodySmall)),
                TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'New email')),
                const SizedBox(height: RvmSpacing.sm),
                TextField(
                    controller: _password,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Your password')),
                const SizedBox(height: RvmSpacing.md),
                FilledButton(
                  onPressed: s.status == WriteStatus.submitting
                      ? null
                      : () => widget.bloc.add(AccountRequestEmail(
                          email: _email.text.trim(), password: _password.text)),
                  child: const Text('Send code'),
                ),
              ],
      ),
    );
  }
}

class _ChangePhoneFlow extends StatefulWidget {
  const _ChangePhoneFlow(
      {required this.bloc, required this.close, this.current});
  final AccountActionBloc bloc;
  final VoidCallback close;
  final String? current;
  @override
  State<_ChangePhoneFlow> createState() => _ChangePhoneFlowState();
}

class _ChangePhoneFlowState extends State<_ChangePhoneFlow> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AccountActionBloc, AccountActionState>(
      bloc: widget.bloc,
      listenWhen: (a, b) => a.status != b.status || a.codeSent != b.codeSent,
      listener: (context, s) {
        if (s.codeSent) setState(() => _sent = true);
        if (s.status == WriteStatus.success && !s.codeSent) {
          widget.close();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Phone updated.')));
        }
      },
      builder: (context, s) => _ActionDialog(
        title: _sent ? 'Confirm new number' : 'Change phone number',
        bloc: widget.bloc,
        children: _sent
            ? [
                Text('Enter the code sent by SMS to ${_phone.text.trim()}.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: RvmSpacing.sm),
                TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '6-digit code')),
                const SizedBox(height: RvmSpacing.md),
                FilledButton(
                  onPressed: s.status == WriteStatus.submitting
                      ? null
                      : () => widget.bloc
                          .add(AccountConfirmPhone(_code.text.trim())),
                  child: const Text('Confirm'),
                ),
              ]
            : [
                if (widget.current != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Current: ${widget.current}',
                          style: Theme.of(context).textTheme.bodySmall)),
                TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(labelText: 'New mobile number')),
                const SizedBox(height: RvmSpacing.sm),
                TextField(
                    controller: _password,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Your password')),
                const SizedBox(height: RvmSpacing.md),
                FilledButton(
                  onPressed: s.status == WriteStatus.submitting
                      ? null
                      : () => widget.bloc.add(AccountRequestPhone(
                          phoneNumber: _phone.text.trim(),
                          password: _password.text)),
                  child: const Text('Send code'),
                ),
              ],
      ),
    );
  }
}

class _EnableTwoFactorFlow extends StatefulWidget {
  const _EnableTwoFactorFlow({required this.bloc, required this.close});
  final AccountActionBloc bloc;
  final VoidCallback close;
  @override
  State<_EnableTwoFactorFlow> createState() => _EnableTwoFactorFlowState();
}

class _EnableTwoFactorFlowState extends State<_EnableTwoFactorFlow> {
  final _code = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.bloc.add(const AccountRequestTwoFactor());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AccountActionBloc, AccountActionState>(
      bloc: widget.bloc,
      listenWhen: (a, b) => a.status != b.status || a.codeSent != b.codeSent,
      listener: (context, s) {
        if (s.codeSent) setState(() => _sent = true);
        if (s.status == WriteStatus.success && !s.codeSent) {
          widget.close();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Two-factor is on.')));
        }
      },
      builder: (context, s) => _ActionDialog(
        title: 'Turn on two-factor',
        bloc: widget.bloc,
        children: _sent
            ? [
                Text('Enter the code sent to your verified email.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: RvmSpacing.sm),
                TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '6-digit code')),
                const SizedBox(height: RvmSpacing.md),
                FilledButton(
                  onPressed: s.status == WriteStatus.submitting
                      ? null
                      : () => widget.bloc
                          .add(AccountEnableTwoFactor(_code.text.trim())),
                  child: const Text('Turn on'),
                ),
              ]
            : [
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator()))
              ],
      ),
    );
  }
}

class _DisableTwoFactorForm extends StatefulWidget {
  const _DisableTwoFactorForm({required this.bloc, required this.close});
  final AccountActionBloc bloc;
  final VoidCallback close;
  @override
  State<_DisableTwoFactorForm> createState() => _DisableTwoFactorFormState();
}

class _DisableTwoFactorFormState extends State<_DisableTwoFactorForm> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AccountActionBloc, AccountActionState>(
      bloc: widget.bloc,
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == WriteStatus.success) {
          widget.close();
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Two-factor is off.')));
        }
      },
      builder: (context, s) => _ActionDialog(
          title: 'Turn off two-factor',
          bloc: widget.bloc,
          children: [
            TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Your password')),
            const SizedBox(height: RvmSpacing.md),
            FilledButton(
              onPressed: s.status == WriteStatus.submitting
                  ? null
                  : () =>
                      widget.bloc.add(AccountDisableTwoFactor(_password.text)),
              child: const Text('Turn off'),
            ),
          ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});
  final List<(String, String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    return TeamCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: TeamIconBadge(
                icon: switch (rows[i].$1) {
                  'Email' => Icons.alternate_email_rounded,
                  'Phone' => Icons.phone_iphone_rounded,
                  _ => Icons.verified_user_outlined,
                },
                size: 34,
                iconSize: 16,
                radius: 10,
              ),
              title: Text(rows[i].$2,
                  style: Theme.of(context).textTheme.bodyMedium),
              subtitle: Text(rows[i].$1,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 10)),
              trailing: rows[i].$3 == null
                  ? null
                  : TeamPill(
                      label: rows[i].$3!,
                      tone: rows[i].$3 == 'Verified' || rows[i].$3 == 'On'
                          ? TeamPillTone.success
                          : TeamPillTone.warning,
                      dense: true,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

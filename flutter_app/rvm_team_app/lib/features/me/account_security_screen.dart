import 'dart:convert';

import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app_feedback.dart';
import '../../app_validators.dart';
import '../../bloc/team_auth_bloc.dart';
import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/image_crop_screen.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import 'bloc/account_action_bloc.dart';

/// Account & security for the signed-in person — the existing `/api/me/*`
/// endpoints behind the web Settings page.
class AccountSecurityScreen extends StatelessWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Issue #13: an attendance-only sign-in has no users row, so the
    // Scheduler's /api/me guard rejects its punch token. That sign-in gets the
    // ESS's own small account surface instead; a portal session keeps the
    // Scheduler screen exactly as before.
    final attendance = context.select<TeamAuthBloc, bool>(
        (b) => b.state.identity?.attendance == true);
    if (attendance) return const _AttendanceAccountScreen();
    return BlocProvider(
      create: (_) => getIt<MeBloc>()..add(const LoadRequested()),
      child: const _SecurityView(),
    );
  }
}

/// Account & Security for an attendance-only sign-in (issue #13).
///
/// Email and phone are the person's login identifiers on the HR record, so
/// they are read-only here and the screen says HR owns them; the data-request
/// flow (A8) is the path. Only the password is changed here, through the ESS,
/// and a change ends every ESS sign-in for the person — including this one.
class _AttendanceAccountScreen extends StatelessWidget {
  const _AttendanceAccountScreen();

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<LoadBloc<EssAccount>>()..add(const LoadRequested()),
      child: const _AttendanceSecurityView(),
    );
  }
}

class _AttendanceSecurityView extends StatelessWidget {
  const _AttendanceSecurityView();

  @override
  Widget build(BuildContext context) {
    return TeamScaffold(
      title: 'Account & Security',
      body: BlocBuilder<LoadBloc<EssAccount>, LoadState<EssAccount>>(
        builder: (context, state) {
          if (state.status == LoadStatus.initial ||
              (state.status == LoadStatus.loading && state.data == null)) {
            return const AppLoading();
          }
          if (state.status == LoadStatus.failure && state.data == null) {
            return AppError(
              message: state.failure?.message ?? 'Could not load your account.',
              onRetry: () => context
                  .read<LoadBloc<EssAccount>>()
                  .add(const LoadRefreshed()),
            );
          }
          return _body(context, state.data!);
        },
      ),
    );
  }

  Widget _body(BuildContext context, EssAccount account) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const TeamSectionHeader(
            title: 'Sign-in details', caption: 'Kept private to you'),
        const SizedBox(height: 8),
        _InfoCard(rows: [
          if (account.username != null)
            _InfoRow('Employee code', account.username!),
          _InfoRow(
            'Email',
            account.email ?? 'Not set',
            status: account.email == null
                ? null
                : (account.emailVerified ? 'Verified' : 'Unverified'),
          ),
          _InfoRow('Phone', account.phoneNumber ?? 'Not set'),
        ]),
        if (account.note != null) ...[
          const SizedBox(height: RvmSpacing.md),
          TeamNotice(
            icon: Icons.info_outline_rounded,
            tone: TeamPillTone.warning,
            text: account.note!,
          ),
          const SizedBox(height: RvmSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => context.push('/me/data-requests'),
            icon: const Icon(Icons.privacy_tip_outlined, size: 18),
            label: const Text('Ask HR to change my email or phone'),
          ),
        ],
        const SizedBox(height: RvmSpacing.lg),
        const TeamSectionHeader(
            title: 'Password', caption: 'The password this sign-in uses'),
        const SizedBox(height: 8),
        _AttendancePasswordCard(enabled: account.canChangePassword),
        const SizedBox(height: RvmSpacing.md),
        Center(
          child: Text(
            'Changing your password signs you out on this phone and every other phone.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// The ESS password change (`POST /me/password`). A wrong current password is
/// a 401 WRONG_PASSWORD and is shown as-is; it never signs the person out.
class _AttendancePasswordCard extends StatefulWidget {
  const _AttendancePasswordCard({required this.enabled});
  final bool enabled;

  @override
  State<_AttendancePasswordCard> createState() =>
      _AttendancePasswordCardState();
}

class _AttendancePasswordCardState extends State<_AttendancePasswordCard> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text;
    final next = _next.text;
    final confirm = _confirm.text;
    if (next.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'The new passwords do not match.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await getIt<EssRepository>().changeMyPassword(
        currentPassword: current,
        newPassword: next,
        confirmPassword: confirm,
      );
      if (!mounted) return;
      showAppMessage('Password changed. Sign in again with the new one.');
      // The server ended every live ESS sign-in, this one included.
      context.read<TeamAuthBloc>().add(const TeamSignedOut());
    } on Failure catch (f) {
      // 'Wrong password.' for a real refusal (401 WRONG_PASSWORD).
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not change the password. Try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return TeamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Current password',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'New password (min. 8 characters)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Confirm new password',
                border: OutlineInputBorder()),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: text.bodySmall?.copyWith(color: RvmColors.danger)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: !widget.enabled || _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Update password'),
          ),
        ],
      ),
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
          if (state.status == LoadStatus.initial ||
              (state.status == LoadStatus.loading && state.data == null)) {
            return const AppLoading();
          }
          if (state.status == LoadStatus.failure && state.data == null) {
            return AppError(
              message: state.failure?.message ?? 'Could not load your account.',
              onRetry: () => context.read<MeBloc>().add(const LoadRefreshed()),
            );
          }
          return _body(context, state.data!);
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
          _InfoRow(
            'Email',
            p.email ?? 'Not set',
            status: p.emailVerified
                ? 'Verified'
                : (p.email == null ? null : 'Unverified'),
            onVerify: p.email != null && !p.emailVerified
                ? () => _verifyEmail(context, p)
                : null,
          ),
          _InfoRow('Phone', p.phoneNumber ?? 'Not set'),
          _InfoRow('Two-factor', p.twoFactorEnabled ? 'On' : 'Off',
              status: p.twoFactorEnabled ? 'On' : 'Off'),
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
    FilePickerResult? result;
    try {
      result = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('Could not open the photo picker.')));
      }
      return;
    }
    final file = result?.files.single;
    var bytes = file?.bytes;
    if (file == null || bytes == null || !context.mounted) return;
    // E10: the ESS path works for attendance-only staff too; the Scheduler upload is the
    // fallback for portal logins (e.g. an unsupported image type on the ESS).
    var contentType = switch (file.extension?.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    // Give the person the same crop option the Wall uses. Cancelling the crop
    // keeps the photo as picked.
    final cropped = await editImageBytes(context, bytes);
    if (!context.mounted) return;
    if (cropped != null) bytes = cropped;
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

  /// Verifies the address already on the account. The Scheduler's email-change
  /// route accepts the current address while it is unverified and sends a code
  /// to it; confirming that code stamps `email_verified_at`, so no new endpoint
  /// is needed and the address itself never moves.
  void _verifyEmail(BuildContext context, TeamProfile p) {
    final email = p.email;
    if (email == null || email.isEmpty) return;
    _showActionDialog(
      context,
      build: (close, bloc) =>
          _VerifyEmailFlow(bloc: bloc, close: close, email: email),
    );
  }

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
          // The default 40px side insets squeeze forms on phones; 16px keeps
          // every row (rules, buttons) inside the screen on 320px devices.
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
          showAppMessage('Password changed.');
          widget.close();
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
              // Wrap, not Row: on narrow phones the three rules exceed the
              // dialog width by ~10px ("overflowed by 9.8 pixels"). Wrapping
              // keeps every rule visible on any screen width.
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  _rule(context, _new.text.length >= 8, '8+ chars'),
                  _rule(context, _new.text.contains(RegExp(r'[A-Z]')),
                      'Uppercase'),
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
                              if (_old.text.isEmpty) {
                                showAppMessage('Enter your current password.');
                                return;
                              }
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
          showAppMessage('Email updated.');
          widget.close();
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
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration:
                        const InputDecoration(labelText: '6-digit code')),
                const SizedBox(height: RvmSpacing.md),
                FilledButton(
                  onPressed: s.status == WriteStatus.submitting
                      ? null
                      : () {
                          if (!RegExp(r'^\d{6}$')
                              .hasMatch(_code.text.trim())) {
                            showAppMessage('Enter the 6-digit code.');
                            return;
                          }
                          widget.bloc
                              .add(AccountConfirmEmail(_code.text.trim()));
                        },
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
                      : () {
                          if (!isValidEmail(_email.text)) {
                            showAppMessage(
                                'Enter a valid email address.');
                            return;
                          }
                          if (_password.text.isEmpty) {
                            showAppMessage('Enter your password.');
                            return;
                          }
                          widget.bloc.add(AccountRequestEmail(
                              email: _email.text.trim(),
                              password: _password.text));
                        },
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
          showAppMessage('Phone updated.');
          widget.close();
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
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration:
                        const InputDecoration(labelText: '6-digit code')),
                const SizedBox(height: RvmSpacing.md),
                FilledButton(
                  onPressed: s.status == WriteStatus.submitting
                      ? null
                      : () {
                          if (!RegExp(r'^\d{6}$')
                              .hasMatch(_code.text.trim())) {
                            showAppMessage('Enter the 6-digit code.');
                            return;
                          }
                          widget.bloc
                              .add(AccountConfirmPhone(_code.text.trim()));
                        },
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
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                        labelText: 'New mobile number',
                        hintText: '10-digit mobile number')),
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
                      : () {
                          if (!isValidPhone10(_phone.text)) {
                            showAppMessage(
                                'Enter a valid 10-digit mobile number.');
                            return;
                          }
                          if (_password.text.isEmpty) {
                            showAppMessage('Enter your password.');
                            return;
                          }
                          widget.bloc.add(AccountRequestPhone(
                              phoneNumber: _phone.text.trim(),
                              password: _password.text));
                        },
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
          showAppMessage('Two-factor is on.');
          widget.close();
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
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration:
                        const InputDecoration(labelText: '6-digit code')),
                const SizedBox(height: RvmSpacing.md),
                FilledButton(
                  onPressed: s.status == WriteStatus.submitting
                      ? null
                      : () {
                          if (!RegExp(r'^\d{6}$')
                              .hasMatch(_code.text.trim())) {
                            showAppMessage('Enter the 6-digit code.');
                            return;
                          }
                          widget.bloc
                              .add(AccountEnableTwoFactor(_code.text.trim()));
                        },
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
          showAppMessage('Two-factor is off.');
          widget.close();
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
                  : () {
                      if (_password.text.isEmpty) {
                        showAppMessage('Enter your password.');
                        return;
                      }
                      widget.bloc
                          .add(AccountDisableTwoFactor(_password.text));
                    },
              child: const Text('Turn off'),
            ),
          ]),
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, this.value, {this.status, this.onVerify});
  final String label;
  final String value;
  final String? status;
  final VoidCallback? onVerify;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});
  final List<_InfoRow> rows;

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
                icon: switch (rows[i].label) {
                  'Email' => Icons.alternate_email_rounded,
                  'Phone' => Icons.phone_iphone_rounded,
                  _ => Icons.verified_user_outlined,
                },
                size: 34,
                iconSize: 16,
                radius: 10,
              ),
              title: Text(rows[i].value,
                  style: Theme.of(context).textTheme.bodyMedium),
              subtitle: Text(rows[i].label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 10)),
              trailing: _trailing(rows[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _trailing(_InfoRow row) {
    final status = row.status;
    if (status == null) return null;
    if (status == 'Unverified') {
      return OutlinedButton(
        onPressed: row.onVerify,
        style: OutlinedButton.styleFrom(
          foregroundColor: RvmColors.danger,
          side: const BorderSide(color: RvmColors.danger),
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
        ),
        child: const Text('Verify Now',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
      );
    }
    if (status == 'Verified') {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 14, color: RvmColors.success),
          SizedBox(width: 3),
          Text('Verified',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: RvmColors.success)),
        ],
      );
    }
    return TeamPill(
      label: status,
      tone: status == 'On' ? TeamPillTone.success : TeamPillTone.neutral,
      dense: true,
    );
  }
}

/// Sends a code to the address already on the account (still unverified) and
/// confirms it. Distinct from [_ChangeEmailFlow], which moves the address.
class _VerifyEmailFlow extends StatefulWidget {
  const _VerifyEmailFlow(
      {required this.bloc, required this.close, required this.email});
  final AccountActionBloc bloc;
  final VoidCallback close;
  final String email;
  @override
  State<_VerifyEmailFlow> createState() => _VerifyEmailFlowState();
}

class _VerifyEmailFlowState extends State<_VerifyEmailFlow> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
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
          showAppMessage('Email verified.');
          widget.close();
        }
      },
      builder: (context, s) => _ActionDialog(
        title: _sent ? 'Confirm your email' : 'Verify your email',
        bloc: widget.bloc,
        children: _sent
            ? [
                Text('Enter the 6-digit code sent to ${widget.email}.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: RvmSpacing.sm),
                TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration:
                        const InputDecoration(labelText: '6-digit code')),
                const SizedBox(height: RvmSpacing.md),
                FilledButton(
                  onPressed: s.status == WriteStatus.submitting
                      ? null
                      : () {
                          if (!RegExp(r'^\d{6}$')
                              .hasMatch(_code.text.trim())) {
                            showAppMessage('Enter the 6-digit code.');
                            return;
                          }
                          widget.bloc
                              .add(AccountConfirmEmail(_code.text.trim()));
                        },
                  child: const Text('Verify'),
                ),
              ]
            : [
                Text(
                    'We will send a code to ${widget.email}. Enter your current '
                    'password to prove it is you.',
                    style: Theme.of(context).textTheme.bodySmall),
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
                      : () {
                          if (!isValidEmail(widget.email)) {
                            showAppMessage(
                                'Your account email looks invalid. Ask HR to correct it.');
                            return;
                          }
                          if (_password.text.isEmpty) {
                            showAppMessage('Enter your current password.');
                            return;
                          }
                          widget.bloc.add(AccountRequestEmail(
                              email: widget.email, password: _password.text));
                        },
                  child: const Text('Send code'),
                ),
              ],
      ),
    );
  }
}

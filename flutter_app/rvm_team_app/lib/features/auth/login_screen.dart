import 'dart:async';

import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app_validators.dart';
import '../../auth/team_branches.dart';
import '../../bloc/team_auth_bloc.dart';
import '../../data/repositories/ess_repository.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _branchField = GlobalKey<FormFieldState<String>>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _attIdentifier = TextEditingController();
  final _attPassword = TextEditingController();
  final _attCode = TextEditingController();
  final _attFormKey = GlobalKey<FormState>();
  String? _branch;
  bool _obscure = true;

  // A5 one-field sign-in: the ESS resolver tells us which branches sign this
  // identifier in. Until it answers, the full branch list is offered.
  List<String> _branches = teamBranches;
  String? _resolverHint;
  Timer? _resolveDebounce;

  @override
  void dispose() {
    _resolveDebounce?.cancel();
    _username.dispose();
    _password.dispose();
    _attIdentifier.dispose();
    _attPassword.dispose();
    _attCode.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _resolveDebounce?.cancel();
    final identifier = value.trim();
    if (identifier.isEmpty) {
      setState(() {
        _branches = teamBranches;
        _resolverHint = null;
      });
      return;
    }
    _resolveDebounce =
        Timer(const Duration(milliseconds: 450), () => _resolve(identifier));
  }

  Future<void> _resolve(String identifier) async {
    try {
      final resolution = await getIt<EssRepository>().resolveSignIn(identifier);
      if (!mounted || _username.text.trim() != identifier) return;
      var clearedBranch = false;
      setState(() {
        switch (resolution.kind) {
          case 'attendance':
            _resolverHint =
                'This account signs in with attendance ${resolution.methods.join(' or ')}. '
                'That flow is not in this app yet — use the portal password.';
          case 'unknown':
            _resolverHint =
                'No single account matched. Check the username or phone.';
          default:
            _resolverHint = null;
        }
        if (resolution.locationNames.isNotEmpty) {
          // Never let a partial resolver reply remove a known branch from the
          // picker. Keep the fixed list and add anything new the server names.
          _branches = {
            ...teamBranches,
            ...resolution.locationNames,
          }.toList(growable: false);
          if (_branch != null && !_branches.contains(_branch)) {
            _branch = null;
            clearedBranch = true;
          }
        }
      });
      if (clearedBranch) _branchField.currentState?.didChange(null);
    } catch (_) {
      // Resolver is an enhancement; a failure leaves the full branch list.
    }
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    context.read<TeamAuthBloc>().add(TeamLoginSubmitted(
          username: _username.text.trim(),
          password: _password.text,
          locationName: _branch!,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: SafeArea(
              child: BlocBuilder<TeamAuthBloc, TeamAuthState>(
                builder: (context, state) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: TeamCard(
                        padding: const EdgeInsets.all(20),
                        child: _content(context, state),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'RVM Beyond Pvt Ltd',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: RvmColors.subtle,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, TeamAuthState state) {
    if (state.twoFactor != null) {
      return _TwoFactorStep(challenge: state.twoFactor!, state: state);
    }
    if (state.attendanceCode != null) {
      return _attendanceCodeStep(context, state);
    }
    if (state.attendanceMode) return _attendanceForm(context, state);
    return _form(context, state);
  }

  /// Attendance-only sign-in (A2) for staff with no portal login.
  Widget _attendanceForm(BuildContext context, TeamAuthState state) {
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _attFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Attendance sign-in',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: RvmSpacing.xs),
          Text(
              'For staff without a portal login. Use your phone, email or employee code.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: RvmSpacing.xl),
          TextFormField(
            controller: _attIdentifier,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Phone, email or employee code',
                prefixIcon: Icon(Icons.badge_outlined)),
            validator: (v) => validateIdentifier(v ?? '',
                emptyMessage: 'Enter your phone, email or employee code'),
          ),
          const SizedBox(height: RvmSpacing.md),
          TextFormField(
            controller: _attPassword,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Attendance password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter your password' : null,
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: RvmSpacing.md),
            _ErrorNote(state.errorMessage!),
          ],
          const SizedBox(height: RvmSpacing.lg),
          FilledButton(
            onPressed: state.submitting ? null : _submitAttendance,
            child: state.submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Text('Sign in'),
          ),
          const SizedBox(height: RvmSpacing.sm),
          TextButton(
            onPressed: state.submitting ? null : _requestCode,
            child: const Text('Send me a sign-in code instead'),
          ),
          TextButton(
            onPressed: state.submitting
                ? null
                : () => context
                    .read<TeamAuthBloc>()
                    .add(const TeamAttendanceModeToggled(false)),
            child: const Text('Back to portal sign-in'),
          ),
        ],
      ),
    );
  }

  Widget _attendanceCodeStep(BuildContext context, TeamAuthState state) {
    final scheme = Theme.of(context).colorScheme;
    final code = state.attendanceCode!;
    return Form(
      key: _attFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Enter the code',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: RvmSpacing.xs),
          Text(
            'We sent a 6-digit code to ${code.sentTo ?? 'you'} by ${code.channel ?? 'SMS'}. '
            'It is valid for ${code.ttlMinutes} minutes.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: RvmSpacing.xl),
          TextFormField(
            controller: _attCode,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6)
            ],
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(letterSpacing: 8),
            onFieldSubmitted: (_) => _submitCode(code.challengeId),
            decoration: const InputDecoration(
                labelText: 'Sign-in code',
                prefixIcon: Icon(Icons.pin_outlined)),
            validator: (v) => RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '')
                ? null
                : 'Enter the 6-digit code',
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: RvmSpacing.md),
            _ErrorNote(state.errorMessage!),
          ],
          const SizedBox(height: RvmSpacing.lg),
          FilledButton(
            onPressed:
                state.submitting ? null : () => _submitCode(code.challengeId),
            child: state.submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Text('Verify and sign in'),
          ),
          const SizedBox(height: RvmSpacing.sm),
          TextButton(
            onPressed: state.submitting
                ? null
                : () => context
                    .read<TeamAuthBloc>()
                    .add(const TeamAttendanceBack()),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  void _submitAttendance() {
    if (!(_attFormKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    context.read<TeamAuthBloc>().add(TeamAttendanceLoginSubmitted(
          identifier: _attIdentifier.text.trim(),
          password: _attPassword.text,
        ));
  }

  void _requestCode() {
    final identifier = _attIdentifier.text.trim();
    final idError = validateIdentifier(identifier,
        emptyMessage: 'Enter your phone, email or employee code first.');
    if (idError != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(idError)));
      return;
    }
    context.read<TeamAuthBloc>().add(TeamAttendanceCodeRequested(identifier));
  }

  void _submitCode(String challengeId) {
    if (!(_attFormKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    context.read<TeamAuthBloc>().add(TeamAttendanceCodeSubmitted(
        challengeId: challengeId, code: _attCode.text.replaceAll(' ', '')));
  }

  Widget _form(BuildContext context, TeamAuthState state) {
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AppLogo(),
          const SizedBox(height: RvmSpacing.lg),
          Text('Sign in to Team RVM',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: RvmSpacing.xs),
          Text('Use your RVM portal username or phone and password.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: RvmSpacing.xl),
          TextFormField(
            controller: _username,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            onChanged: _onUsernameChanged,
            decoration: const InputDecoration(
                labelText: 'Username or phone',
                prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => validateIdentifier(v ?? '',
                emptyMessage: 'Enter your username or phone'),
          ),
          if (_resolverHint != null) ...[
            const SizedBox(height: RvmSpacing.sm),
            Text(_resolverHint!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: RvmSpacing.md),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter your password' : null,
          ),
          const SizedBox(height: RvmSpacing.md),
          FormField<String>(
            key: _branchField,
            initialValue: _branch,
            validator: (v) => v == null ? 'Select your branch' : null,
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 18, color: RvmColors.clay),
                    const SizedBox(width: 6),
                    Text('Branch',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                // All branches are on screen at once. A dropdown clipped this
                // list to two rows on the phone and made the other branches look
                // missing (KP, 26 Oct); a choice chip always shows every one.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in _branches)
                      ChoiceChip(
                        label: Text(b),
                        selected: _branch == b,
                        onSelected: state.submitting
                            ? null
                            : (selected) {
                                setState(() => _branch = b);
                                field.didChange(b);
                              },
                      ),
                  ],
                ),
                if (field.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      field.errorText!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 4),
                Text('Company-wide accounts can pick any branch.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: RvmSpacing.md),
            _ErrorNote(state.errorMessage!),
          ],
          const SizedBox(height: RvmSpacing.lg),
          FilledButton(
            onPressed: state.submitting ? null : _submit,
            child: state.submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Text('Sign in'),
          ),
          const SizedBox(height: RvmSpacing.sm),
          TextButton(
              onPressed: () => context.push('/forgot'),
              child: const Text('Forgot password?')),
          const Divider(height: RvmSpacing.lg),
          TextButton.icon(
            onPressed: state.submitting
                ? null
                : () => context
                    .read<TeamAuthBloc>()
                    .add(const TeamAttendanceModeToggled(true)),
            icon: const Icon(Icons.fingerprint),
            label: const Text(
                'Staff without a portal login? Sign in with attendance'),
          ),
        ],
      ),
    );
  }
}

/// The Team RVM app mark on its own, in place of the old people icon. The
/// company line sits at the bottom of the sign-in screen (KP, 26 Oct).
class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/team_rvm_logo.png',
      height: 38,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Text('rvm',
          style: TextStyle(
              color: RvmColors.clay,
              fontWeight: FontWeight.w800,
              fontSize: 26)),
    );
  }
}

class _TwoFactorStep extends StatefulWidget {
  const _TwoFactorStep({required this.challenge, required this.state});
  final TeamTwoFactorChallenge challenge;
  final TeamAuthState state;

  @override
  State<_TwoFactorStep> createState() => _TwoFactorStepState();
}

class _TwoFactorStepState extends State<_TwoFactorStep> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _verify() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    context.read<TeamAuthBloc>().add(TeamTwoFactorSubmitted(_code.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = widget.state;
    final challenge = widget.challenge;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: RvmColors.claySoft,
              borderRadius: BorderRadius.circular(RvmRadii.lg),
            ),
            child: const Icon(Icons.mark_email_read_outlined,
                size: 26, color: RvmColors.clay),
          ),
          const SizedBox(height: RvmSpacing.lg),
          Text('Check your email', style: theme.textTheme.headlineSmall),
          const SizedBox(height: RvmSpacing.xs),
          Text(
            'Two-step sign-in is on for this account. Enter the 6-digit code sent to '
            '${challenge.sentTo ?? 'your email'}.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: RvmSpacing.xl),
          TextFormField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6)
            ],
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 8),
            onFieldSubmitted: (_) => _verify(),
            decoration: const InputDecoration(
                labelText: 'Sign-in code',
                prefixIcon: Icon(Icons.pin_outlined)),
            validator: (v) => RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '')
                ? null
                : 'Enter the 6-digit code',
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: RvmSpacing.md),
            _ErrorNote(state.errorMessage!),
          ],
          const SizedBox(height: RvmSpacing.lg),
          FilledButton(
            onPressed: state.submitting ? null : _verify,
            child: state.submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Text('Verify and sign in'),
          ),
          const SizedBox(height: RvmSpacing.sm),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: state.submitting
                    ? null
                    : () => context
                        .read<TeamAuthBloc>()
                        .add(const TeamTwoFactorResendRequested()),
                child: const Text('Resend code'),
              ),
              TextButton(
                onPressed: state.submitting
                    ? null
                    : () => context
                        .read<TeamAuthBloc>()
                        .add(const TeamTwoFactorCancelled()),
                child: const Text('Use a different account'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(RvmSpacing.sm + 2),
      decoration: BoxDecoration(
        color: RvmColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(RvmRadii.sm),
        border: Border.all(color: RvmColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: RvmColors.danger),
          const SizedBox(width: RvmSpacing.sm),
          Expanded(
            child: Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: RvmColors.danger)),
          ),
        ],
      ),
    );
  }
}

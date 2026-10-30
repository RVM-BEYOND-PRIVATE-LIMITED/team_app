import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app_validators.dart';
import '../../bloc/forgot_password_bloc.dart';
import '../../injection.dart';
import '../../widgets/states.dart';

/// Code-based reset: request a code to the account's verified email or, when
/// there is none, its registered phone; then set a new password. (Never the
/// retired username+phone reset.)
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ForgotPasswordBloc>(),
      child: const _ForgotPasswordView(),
    );
  }
}

class _ForgotPasswordView extends StatefulWidget {
  const _ForgotPasswordView();

  @override
  State<_ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<_ForgotPasswordView> {
  final _identifier = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: BlocConsumer<ForgotPasswordBloc, ForgotState>(
        listener: (context, state) {
          if (state.done) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                  content:
                      Text('Password changed. Sign in with the new one.')));
            context.go('/login');
          }
        },
        builder: (context, state) {
          if (state.done) return const AppLoading();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(RvmSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: state.codeSent
                    ? _confirmForm(context, state)
                    : _requestForm(context, state),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _requestForm(BuildContext context, ForgotState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Enter your username, phone or email',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: RvmSpacing.xs),
        Text(
            'We will send a 6-digit code to your verified email, or to your registered phone by SMS.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: RvmSpacing.lg),
        TextField(
          controller: _identifier,
          decoration: const InputDecoration(
              labelText: 'Username, phone or email',
              prefixIcon: Icon(Icons.person_outline)),
        ),
        if (state.error != null || _localError != null) ...[
          const SizedBox(height: RvmSpacing.md),
          _Error(state.error ?? _localError!),
        ],
        const SizedBox(height: RvmSpacing.lg),
        FilledButton(
          onPressed: state.submitting
              ? null
              : () {
                  final id = _identifier.text.trim();
                  final idError = validateIdentifier(id,
                      emptyMessage: 'Enter your username, phone or email.');
                  if (idError != null) {
                    setState(() => _localError = idError);
                    return;
                  }
                  setState(() => _localError = null);
                  FocusScope.of(context).unfocus();
                  context.read<ForgotPasswordBloc>().add(ForgotRequested(id));
                },
          child: state.submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4))
              : const Text('Get a code'),
        ),
      ],
    );
  }

  Widget _confirmForm(BuildContext context, ForgotState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Enter the code and choose a new password',
            style: Theme.of(context).textTheme.titleMedium),
        if (state.message != null) ...[
          const SizedBox(height: RvmSpacing.xs),
          Text(state.message!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: RvmSpacing.lg),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6)
          ],
          decoration: const InputDecoration(
              labelText: '6-digit code', prefixIcon: Icon(Icons.pin_outlined)),
        ),
        const SizedBox(height: RvmSpacing.md),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: 'New password (8+ characters)',
              prefixIcon: Icon(Icons.lock_outline)),
        ),
        if (state.error != null || _localError != null) ...[
          const SizedBox(height: RvmSpacing.md),
          _Error(state.error ?? _localError!),
        ],
        const SizedBox(height: RvmSpacing.lg),
        FilledButton(
          onPressed: state.submitting
              ? null
              : () {
                  final code = _code.text.trim();
                  final pwd = _password.text;
                  if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                    setState(() => _localError = 'Enter the 6-digit code.');
                    return;
                  }
                  if (pwd.length < 8) {
                    setState(() => _localError = 'Use at least 8 characters.');
                    return;
                  }
                  setState(() => _localError = null);
                  FocusScope.of(context).unfocus();
                  context.read<ForgotPasswordBloc>().add(ForgotConfirmed(
                        identifier: _identifier.text.trim(),
                        code: code,
                        newPassword: pwd,
                      ));
                },
          child: state.submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4))
              : const Text('Change password'),
        ),
        const SizedBox(height: RvmSpacing.sm),
        TextButton(
          onPressed: state.submitting
              ? null
              : () =>
                  context.read<ForgotPasswordBloc>().add(const ForgotReset()),
          child: const Text('Start over'),
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error(this.message);
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
      child: Text(message,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: RvmColors.danger)),
    );
  }
}

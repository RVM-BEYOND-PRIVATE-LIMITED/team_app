import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_validators.dart';
import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import '../../widgets/team_kit.dart';

/// Phase 2C, KP 3: my bank details, saved with explicit consent. Only I see the full number.
class BankDetailsScreen extends StatefulWidget {
  const BankDetailsScreen({super.key});

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  final _bank = TextEditingController();
  final _branch = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  final _upi = TextEditingController();
  final _consentName = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  bool _showAccount = false;
  Failure? _failure;
  BankDetails? _existing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bank.dispose();
    _branch.dispose();
    _account.dispose();
    _ifsc.dispose();
    _upi.dispose();
    _consentName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bank = await getIt<EssRepository>().myBankDetails();
      if (!mounted) return;
      setState(() {
        _existing = bank;
        _seed(bank);
        _editing = bank == null;
        _failure = null;
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

  void _seed(BankDetails? bank) {
    _bank.text = bank?.bankName ?? '';
    _branch.text = bank?.branchName ?? '';
    _account.text = bank?.accountNumber ?? '';
    _ifsc.text = bank?.ifscCode ?? '';
    _upi.text = bank?.upiId ?? '';
    _consentName.text = bank?.consentName ?? '';
  }

  void _startEditing() => setState(() {
        _seed(_existing);
        _showAccount = false;
        _editing = true;
      });

  void _cancelEditing() => setState(() {
        _seed(_existing);
        _showAccount = false;
        _editing = false;
      });

  Future<void> _save() async {
    final bankName = _bank.text.trim();
    final account = _account.text.replaceAll(' ', '').trim();
    final ifsc = _ifsc.text.trim().toUpperCase();
    final upi = _upi.text.trim();
    final consent = _consentName.text.trim();
    if (bankName.length < 2) {
      _snack('Enter your bank name.');
      return;
    }
    if (!isValidAccountNumber(account)) {
      _snack('Account number is 9 to 18 digits, no letters.');
      return;
    }
    if (!isValidIfsc(ifsc)) {
      _snack('IFSC looks like SBIN0010490: 4 letters, a 0, then 6 characters.');
      return;
    }
    if (upi.isNotEmpty && !isValidUpi(upi)) {
      _snack('UPI ID looks like yourname@bank.');
      return;
    }
    if (consent.isEmpty) {
      _snack('Type your full name to consent.');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await getIt<EssRepository>().saveBankDetails(
        bankName: bankName,
        branchName: _branch.text.trim().isEmpty ? null : _branch.text.trim(),
        accountNumber: account,
        ifscCode: ifsc,
        upiId: _upi.text.trim().isEmpty ? null : _upi.text.trim(),
        consentName: consent,
      );
      if (!mounted) return;
      setState(() {
        _existing = saved;
        _seed(saved);
        _showAccount = false;
        _editing = false;
      });
      _snack('Bank details saved.');
    } on Failure catch (f) {
      _snack(f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RvmColors.ivory,
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Bank Details',
            subtitle: const Text('Saved securely for direct deposit payroll'),
            leading: _HeaderBack(onTap: () => Navigator.of(context).maybePop()),
            actions: const [
              TeamPill(
                  label: 'AES-256 Encrypted',
                  tone: TeamPillTone.onDark,
                  icon: Icons.lock_rounded)
            ],
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) {
      return AppError(message: _failure!.message, onRetry: _load);
    }
    return _editing ? _editView() : _readOnlyView();
  }

  Widget _readOnlyView() {
    final bank = _existing;
    if (bank == null) return _editView();
    final text = Theme.of(context).textTheme;
    final account = bank.accountNumber.replaceAll(' ', '');
    final masked = account.length <= 4
        ? account
        : '•••• ${account.substring(account.length - 4)}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, RvmSpacing.xl),
      children: [
        TeamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const TeamIconBadge(
                    icon: Icons.account_balance_rounded,
                    color: RvmColors.clay,
                    background: RvmColors.cream,
                    size: 42,
                    iconSize: 20,
                    radius: 13,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(bank.bankName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleSmall?.copyWith(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.verified_rounded,
                                size: 14, color: RvmColors.success),
                          ],
                        ),
                        Text(bank.branchName ?? 'Branch not set',
                            style: text.bodySmall?.copyWith(fontSize: 10)),
                      ],
                    ),
                  ),
                  if (bank.consentGivenAt != null)
                    const TeamPill(
                        label: 'Primary',
                        tone: TeamPillTone.success,
                        dense: true),
                ],
              ),
              const Divider(height: 24),
              _ReadOnlyField(
                label: 'Account number',
                value: _showAccount ? account : masked,
                trailing: IconButton(
                  tooltip: _showAccount
                      ? 'Hide account number'
                      : 'Show account number',
                  onPressed: () => setState(() => _showAccount = !_showAccount),
                  icon: Icon(
                      _showAccount
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 17),
                  color: RvmColors.subtle,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              _ReadOnlyField(label: 'IFSC code', value: bank.ifscCode),
              if (bank.upiId != null && bank.upiId!.isNotEmpty)
                _ReadOnlyField(label: 'UPI ID', value: bank.upiId!),
              if (bank.consentName != null && bank.consentName!.isNotEmpty)
                _ReadOnlyField(
                    label: 'Consent given by', value: bank.consentName!),
            ],
          ),
        ),
        const SizedBox(height: RvmSpacing.md),
        TeamPrimaryButton(
          label: 'Edit Bank Details',
          icon: Icons.edit_outlined,
          onPressed: _startEditing,
        ),
      ],
    );
  }

  Widget _editView() {
    final text = Theme.of(context).textTheme;
    final account = _account.text.replaceAll(' ', '');
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, RvmSpacing.xl),
      children: [
        _FieldCard(
          label: 'Bank name',
          controller: _bank,
          hint: 'State Bank of India',
        ),
        const SizedBox(height: 10),
        _FieldCard(
          label: 'Branch',
          controller: _branch,
          hint: 'Faridabad Main Branch',
          trailing: Text('Optional',
              style: text.bodySmall
                  ?.copyWith(fontSize: 9, color: RvmColors.subtle)),
        ),
        const SizedBox(height: 10),
        _FieldCard(
          label: 'Account number',
          controller: _account,
          keyboard: TextInputType.number,
          obscureText: !_showAccount,
          focusedBorder: true,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isValidAccountNumber(account))
                Row(
                  children: [
                    const Icon(Icons.check_rounded,
                        size: 11, color: RvmColors.success),
                    const SizedBox(width: 3),
                    Text('Valid format',
                        style: text.labelSmall?.copyWith(
                            fontSize: 8.5,
                            color: RvmColors.success,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
          suffix: IconButton(
            onPressed: () => setState(() => _showAccount = !_showAccount),
            icon: Icon(
                _showAccount
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 17),
            color: RvmColors.subtle,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(height: 10),
        _FieldCard(
          label: 'IFSC code',
          controller: _ifsc,
          hint: 'SBIN0010490',
          uppercase: true,
          trailing: const TeamPill(
              label: 'SBI VERIFIED', tone: TeamPillTone.orange, dense: true),
        ),
        const SizedBox(height: 10),
        _FieldCard(
          label: 'UPI ID',
          controller: _upi,
          hint: '8946991002@ybl',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Reimbursements',
                  style: text.bodySmall
                      ?.copyWith(fontSize: 8.5, color: RvmColors.subtle)),
              const SizedBox(width: 5),
              const TeamPill(
                  label: 'Instant', tone: TeamPillTone.neutral, dense: true),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _FieldCard(
          label: 'Type full name to consent',
          controller: _consentName,
          hint: 'Your full name',
        ),
        const SizedBox(height: RvmSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline_rounded,
                size: 14, color: RvmColors.muted),
            const SizedBox(width: 7),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: text.bodySmall?.copyWith(
                      fontSize: 9.5, height: 1.5, color: RvmColors.muted),
                  children: const [
                    TextSpan(text: 'I authorize '),
                    TextSpan(
                      text: 'Team RVM',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: RvmColors.ink),
                    ),
                    TextSpan(
                      text:
                          ' to securely store and use these bank details for payroll and statutory disbursements under banking compliance standards.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: RvmSpacing.lg),
        TeamPrimaryButton(
          label: 'Save Bank Details',
          icon: Icons.arrow_forward_rounded,
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
        if (_existing != null) ...[
          const SizedBox(height: RvmSpacing.sm),
          TextButton(
            onPressed: _saving ? null : _cancelEditing,
            child: const Text('Cancel'),
          ),
        ],
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: text.labelSmall?.copyWith(
                        fontSize: 8,
                        letterSpacing: 0.7,
                        color: RvmColors.subtle)),
                const SizedBox(height: 3),
                Text(value,
                    style: text.titleSmall?.copyWith(
                      fontSize: 12,
                      letterSpacing: 0.6,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _HeaderBack extends StatelessWidget {
  const _HeaderBack({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 16, color: RvmColors.ivory),
      ),
    );
  }
}

/// A white field card with a tiny uppercase label above the value, matching
/// the bank-details reference.
class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboard,
    this.obscureText = false,
    this.uppercase = false,
    this.focusedBorder = false,
    this.trailing,
    this.suffix,
    this.formatters,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboard;
  final bool obscureText;
  final bool uppercase;
  final bool focusedBorder;
  final Widget? trailing;
  final Widget? suffix;
  final List<TextInputFormatter>? formatters;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 10, 4),
      decoration: BoxDecoration(
        color: RvmColors.white,
        borderRadius: BorderRadius.circular(RvmRadii.md),
        border: Border.all(
            color: focusedBorder ? RvmColors.clay : RvmColors.line,
            width: focusedBorder ? 1.2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label.toUpperCase(),
                    style: text.labelSmall?.copyWith(
                        fontSize: 8.5,
                        letterSpacing: 0.7,
                        color: RvmColors.subtle,
                        fontWeight: FontWeight.w600)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboard,
                  obscureText: obscureText,
                  textCapitalization: uppercase
                      ? TextCapitalization.characters
                      : TextCapitalization.none,
                  inputFormatters: [
                    if (uppercase) UpperCaseTextFormatter(),
                    ...?formatters,
                  ],
                  style: text.titleSmall
                      ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: text.titleSmall?.copyWith(
                        fontSize: 13,
                        color: RvmColors.subtle,
                        fontWeight: FontWeight.w400),
                    isDense: true,
                    filled: false,
                    contentPadding: const EdgeInsets.only(top: 2, bottom: 7),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              if (suffix != null) suffix!,
            ],
          ),
        ],
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

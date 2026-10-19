import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

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
        if (bank != null) {
          _bank.text = bank.bankName;
          _branch.text = bank.branchName ?? '';
          _account.text = bank.accountNumber;
          _ifsc.text = bank.ifscCode;
          _upi.text = bank.upiId ?? '';
          _consentName.text = bank.consentName ?? '';
        }
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

  Future<void> _save() async {
    final bankName = _bank.text.trim();
    final account = _account.text.replaceAll(' ', '').trim();
    final ifsc = _ifsc.text.trim().toUpperCase();
    final consent = _consentName.text.trim();
    if (bankName.length < 2 || account.length < 8 || ifsc.length < 4 || consent.isEmpty) {
      _snack('Fill the bank, account, IFSC and your consent name.');
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
      setState(() => _existing = saved);
      _snack('Bank details saved.');
    } on Failure catch (f) {
      _snack(f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const TeamPageHeader(title: 'Bank details', subtitle: Text('Saved with your consent')),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) return AppError(message: _failure!.message, onRetry: _load);
    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        if (_existing != null)
          Padding(
            padding: const EdgeInsets.only(bottom: RvmSpacing.md),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: Text(_existing!.bankName),
                subtitle: Text('${_existing!.accountNumber} · ${_existing!.ifscCode}'),
                trailing: _existing!.consentGivenAt == null ? null : const Icon(Icons.verified, color: RvmColors.success),
              ),
            ),
          ),
        _field(_bank, 'Bank name'),
        _field(_branch, 'Branch (optional)'),
        _field(_account, 'Account number', keyboard: TextInputType.number),
        _field(_ifsc, 'IFSC code'),
        _field(_upi, 'UPI ID (optional)'),
        _field(_consentName, 'Type your full name to consent'),
        const SizedBox(height: RvmSpacing.sm),
        Text('I consent to RVM storing these details for payroll.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: RvmSpacing.md),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save bank details'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, {TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: RvmSpacing.md),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );
}

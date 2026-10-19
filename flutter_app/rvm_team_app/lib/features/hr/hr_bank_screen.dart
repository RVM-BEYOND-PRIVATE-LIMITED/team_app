import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import 'employee_picker.dart';

/// Phase 2C, KP 3: HR reads one employee's bank details, masked to the last four and audited.
class HrBankScreen extends StatefulWidget {
  const HrBankScreen({super.key});

  @override
  State<HrBankScreen> createState() => _HrBankScreenState();
}

class _HrBankScreenState extends State<HrBankScreen> {
  OrgCard? _employee;
  bool _loading = false;
  Failure? _failure;
  BankDetails? _bank;

  Future<void> _pick() async {
    final person = await pickEmployee(context, title: 'Bank details for…');
    if (person == null || !mounted) return;
    setState(() => _employee = person);
    await _load();
  }

  Future<void> _load() async {
    final employee = _employee;
    if (employee == null) return;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final bank = await getIt<EssRepository>().hrEmployeeBank(employee.id);
      if (!mounted) return;
      setState(() {
        _bank = bank;
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
          TeamPageHeader(
            title: 'Bank details',
            subtitle: Text(_employee?.fullName ?? 'Pick an employee'),
            actions: [IconButton(tooltip: 'Choose employee', onPressed: _pick, icon: const Icon(Icons.person_search))],
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_employee == null) {
      return Center(
        child: FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.person_search), label: const Text('Choose an employee')),
      );
    }
    if (_loading) return const AppLoading();
    if (_failure != null) return AppError(message: _failure!.message, onRetry: _load);
    final bank = _bank;
    if (bank == null) return const AppEmpty(icon: Icons.account_balance_outlined, message: 'No bank details saved.');
    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(RvmSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Bank', bank.bankName),
                if (bank.branchName != null) _row('Branch', bank.branchName!),
                _row('Account', bank.accountNumber),
                _row('IFSC', bank.ifscCode),
                if (bank.upiId != null) _row('UPI', bank.upiId!),
                if (bank.consentName != null) _row('Consent', bank.consentName!),
                if (bank.consentGivenAt != null) _row('Consent at', bank.consentGivenAt!.toLocal().toString().split('.').first),
              ],
            ),
          ),
        ),
        const SizedBox(height: RvmSpacing.md),
        Text('The account number is masked and this read is audited.', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

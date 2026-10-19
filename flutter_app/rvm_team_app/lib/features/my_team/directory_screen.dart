import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// E2/E8: colleague search by name or employee code. Email to everyone; phone where the rule
/// allows it (HR, or a manager above the person) — the server already applied the rule.
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  Failure? _failure;
  List<OrgCard> _people = const [];
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value.trim()));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await getIt<EssRepository>().directory(query: q);
      if (!mounted) return;
      setState(() {
        _people = page.people;
        _truncated = page.truncated;
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
          TeamPageHeader(title: 'Directory', subtitle: const Text('Search a colleague by name or code')),
          Padding(
            padding: const EdgeInsets.fromLTRB(RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, RvmSpacing.sm),
            child: TextField(
              controller: _query,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Name or employee code',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) {
      return AppError(message: _failure!.message, onRetry: () => _search(_query.text.trim()));
    }
    if (_people.isEmpty) {
      return const AppEmpty(icon: Icons.person_search_outlined, message: 'No colleagues matched.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(RvmSpacing.md, RvmSpacing.sm, RvmSpacing.md, RvmSpacing.lg),
      itemCount: _people.length + (_truncated ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
      itemBuilder: (context, i) {
        if (i == _people.length) {
          return const Padding(padding: EdgeInsets.all(8), child: Text('Showing the first 50 — narrow your search.'));
        }
        final c = _people[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Text(c.fullName.trim().isEmpty ? '?' : c.fullName.trim().substring(0, 1).toUpperCase())),
            title: Text(c.fullName),
            subtitle: Text([
              c.designation,
              c.department?.name,
              c.email,
              c.phone,
            ].where((s) => s != null && s.isNotEmpty).join(' · ')),
            trailing: c.noticePeriod
                ? const Icon(Icons.info_outline, color: RvmColors.warning)
                : null,
          ),
        );
      },
    );
  }
}

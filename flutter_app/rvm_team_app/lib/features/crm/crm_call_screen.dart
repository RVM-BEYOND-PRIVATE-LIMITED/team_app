import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../widgets/states.dart';
import 'crm_shared.dart';

/// `/crm/call/:callId?leadId=` — a Call started on the web reaches this phone
/// as an urgent push. One tap opens the dialer with the number fetched once,
/// then the form (team_app #51, item 14). A stale hand-off never opens it.
class CrmCallScreen extends StatefulWidget {
  const CrmCallScreen({super.key, required this.callId, required this.leadId});

  final int callId;
  final int leadId;

  @override
  State<CrmCallScreen> createState() => _CrmCallScreenState();
}

class _CrmCallScreenState extends State<CrmCallScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started) return;
      _started = true;
      openWebCrmCall(context,
          callId: widget.callId, leadId: widget.leadId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('Call')),
      body: const AppLoading(label: 'Opening the dialer…'),
    );
  }
}

import 'package:core_network/core_network.dart';

import '../../../domain/ess_models.dart';

/// The failure to show staff for a request action. A refusal of a switched-off
/// type (team_app #44: excuse-late and short leave, from 12 Nov 2026) gets one
/// fixed line, whatever wording the server used; everything else is unchanged.
Failure requestFailure(Failure f) => f.code == requestTypeSwitchedOffCode
    ? BadResponseFailure(requestTypeSwitchedOffMessage,
        statusCode: f.statusCode, code: f.code)
    : f;

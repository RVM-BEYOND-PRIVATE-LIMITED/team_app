import 'package:get_it/get_it.dart';

import '../../bloc/team_modules_bloc.dart';
import '../../router/module_routes.dart';

/// The modules open for the signed-in person, or nothing where no modules bloc
/// is registered (a widget test or a screen pumped without the app's graph).
/// The shell asks for modules after the ESS capabilities, so reading them here
/// never starts a request.
Set<TeamModule> openTeamModules() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<TeamModulesBloc>()) return const {};
  return getIt<TeamModulesBloc>().state.modules.open;
}

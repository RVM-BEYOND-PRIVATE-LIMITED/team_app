import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// One [GoRoute] of a router, built at a location that matches it.
class BuiltRoute {
  const BuiltRoute({
    required this.path,
    required this.location,
    required this.screen,
  });

  /// The route's full path as declared, e.g. `/work/batch/:id/mark`.
  final String path;

  /// A location the route matches: each `:param` filled in as `p-<param>`.
  final String location;

  /// What the route's builder returns at [location], or null for a route
  /// that has no builder (a page builder or a redirect only).
  final Widget? screen;
}

final _param = RegExp(r':(\w+)');

/// Every [GoRoute] of [router], nested ones and those under a shell route
/// included, each built with [context] at a location that matches it. The
/// builders only construct widgets here; nothing is pumped.
List<BuiltRoute> builtRoutes(GoRouter router, BuildContext context) {
  final built = <BuiltRoute>[];
  void walk(List<RouteBase> routes, String parent) {
    for (final route in routes) {
      var path = parent;
      if (route is GoRoute) {
        path = route.path.startsWith('/')
            ? route.path
            : '${parent.endsWith('/') ? parent : '$parent/'}${route.path}';
        final location = path.replaceAllMapped(_param, (m) => 'p-${m[1]}');
        final builder = route.builder;
        built.add(BuiltRoute(
          path: path,
          location: location,
          screen: builder?.call(
            context,
            GoRouterState(
              router.configuration,
              uri: Uri.parse(location),
              matchedLocation: location,
              fullPath: path,
              pathParameters: {
                for (final m in _param.allMatches(path)) m[1]!: 'p-${m[1]}',
              },
              pageKey: ValueKey<String>(location),
            ),
          ),
        ));
      }
      walk(route.routes, path);
    }
  }

  walk(router.configuration.routes, '');
  return built;
}

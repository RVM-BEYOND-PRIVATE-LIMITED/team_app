import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// A single location fix for the geofenced punch (tasks B6/B7).
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.mocked,
  });

  final double latitude;
  final double longitude;
  final double accuracyM;

  /// `true` when the OS says the fix came from a mocked provider. The Scheduler
  /// cannot tell; the app refuses it and reports it to HR instead (decision 6).
  final bool mocked;
}

/// A refusal the punch screen shows to the person. Kept as a plain exception so
/// it never crosses the network [Failure] boundary.
class LocationException implements Exception {
  const LocationException(this.message, {this.mocked = false});
  final String message;

  /// True when the refuse is because the OS flagged a mocked provider — the app
  /// must not send the punch and instead report it to HR (decision 6).
  final bool mocked;

  @override
  String toString() => message;
}

/// One precise fix, with the permission dance. Never blocks the UI thread.
class LocationService {
  const LocationService();

  Future<LocationFix?> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Turn on location (GPS) and try again.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Location permission is needed to punch.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
          'Location permission is blocked. Enable it for Team RVM in Settings.');
    }

    final position = await _bestEffortPosition();
    if (position == null) return null;
    return LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      mocked: position.isMocked,
    );
  }

  /// Geolocator's own `timeLimit` throws a raw `TimeoutException` when a fix
  /// does not arrive (indoors, or the app was backgrounded). That is a normal
  /// condition here, but the debugger stops on it as if it were a crash. Race
  /// the fix against a plain timer instead: first fix wins, a stalled request
  /// just yields `null` so the caller can show its "step outside" note.
  Future<Position?> _bestEffortPosition() {
    final completer = Completer<Position?>();
    Timer? timer;

    void finish(Position? position) {
      if (completer.isCompleted) return;
      timer?.cancel();
      completer.complete(position);
    }

    timer = Timer(const Duration(seconds: 20), () => finish(null));
    Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
      ),
    ).then(finish, onError: (_, __) => finish(null));
    return completer.future;
  }
}

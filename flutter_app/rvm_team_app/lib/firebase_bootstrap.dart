import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

Future<void>? _ready;

/// One shared `Firebase.initializeApp` for Crashlytics and Messaging. Both
/// start during launch; awaiting the same future avoids racing two native
/// initialisations of the default app.
Future<void> ensureFirebase() => _ready ??= Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

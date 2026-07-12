import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options_stub.dart';

/// Arranque de Firebase.
///
/// Hoy: SIEMPRE contra la Emulator Suite (proyecto demo-salda) porque los
/// proyectos reales aún no existen. `flutterfire configure` (ver CLAUDE.md)
/// generará las opciones reales; entonces este bootstrap usará emuladores
/// solo en debug con --dart-define=USE_EMULATORS=true.
Future<void> bootstrapFirebase() async {
  await Firebase.initializeApp(options: demoFirebaseOptions);

  const useEmulators = bool.fromEnvironment('USE_EMULATORS', defaultValue: true);
  if (useEmulators) {
    // 10.0.2.2 = localhost visto desde el emulador Android.
    final host = defaultTargetPlatform == TargetPlatform.android
        ? const String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2')
        : 'localhost';
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  }

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true, // offline-first (RNF-04)
  );
}

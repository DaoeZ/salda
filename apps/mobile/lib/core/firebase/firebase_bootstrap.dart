import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../config/app_environment.dart';

/// Arranque de Firebase contra el proyecto real (salda-dev).
///
/// Para desarrollar contra la Emulator Suite:
///   flutter run --dart-define=USE_EMULATORS=true
/// (con `firebase emulators:start` en marcha; en el emulador Android el
/// host local es 10.0.2.2).
Future<void> bootstrapFirebase() async {
  final options = DefaultFirebaseOptions.currentPlatform;
  AppEnvironment.validateFirebaseProject(options.projectId);
  await Firebase.initializeApp(options: options);

  const useEmulators = bool.fromEnvironment(
    'USE_EMULATORS',
    defaultValue: false,
  );
  if (useEmulators) {
    final host = defaultTargetPlatform == TargetPlatform.android
        ? const String.fromEnvironment(
            'EMULATOR_HOST',
            defaultValue: '10.0.2.2',
          )
        : 'localhost';
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).useFunctionsEmulator(host, 5001);
  }

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true, // offline-first (RNF-04)
  );
}

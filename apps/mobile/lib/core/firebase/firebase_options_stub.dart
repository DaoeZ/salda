import 'package:firebase_core/firebase_core.dart';

/// Opciones de Firebase para DESARROLLO CONTRA EMULADORES (proyecto
/// `demo-salda`): valores ficticios que los emuladores aceptan. NO son
/// credenciales.
///
/// Cuando existan los proyectos reales (paso 2 de "próximos pasos" en
/// CLAUDE.md), `flutterfire configure` generará `lib/firebase_options.dart`
/// (gitignorado) y `firebase_bootstrap.dart` pasará a importarlo.
const demoFirebaseOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:android:demo',
  messagingSenderId: '000000000000',
  projectId: 'demo-salda',
  storageBucket: 'demo-salda.appspot.com',
);

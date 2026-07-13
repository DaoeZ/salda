// Configuración de cliente de Firebase (proyecto salda-dev).
// Generada desde `firebase apps:sdkconfig`. NO contiene secretos: son
// identificadores públicos de cliente; la seguridad la dan las reglas de
// Firestore/Storage y App Check (ESPECIFICACION.md §13).
// App de prod registrada: 1:215824618765:android:c34f1478fe73ae27d5cc44
// (se cableará con flavors al preparar la release).
import 'package:firebase_core/firebase_core.dart';

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAKqTQES5A4CjhSRqvQVq_zncaXSXp93mY',
    appId: '1:923355592259:android:7e525bf8fd1252b9bac6f6',
    messagingSenderId: '923355592259',
    projectId: 'salda-dev',
    storageBucket: 'salda-dev.firebasestorage.app',
  );
}

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.android:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions non configurato per questa piattaforma.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCyYzngYhHCPBpbQDInuEwhaRUxrgyXO2s',
    appId: '1:362917162978:web:20ea08e0ff8f55702793bb',
    messagingSenderId: '362917162978',
    projectId: 'gussoni-d3153',
    authDomain: 'gussoni-d3153.firebaseapp.com',
    storageBucket: 'gussoni-d3153.firebasestorage.app',
    measurementId: 'G-E2NVE2CDXF',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCyYzngYhHCPBpbQDInuEwhaRUxrgyXO2s',
    appId: '1:362917162978:web:20ea08e0ff8f55702793bb',
    messagingSenderId: '362917162978',
    projectId: 'gussoni-d3153',
    storageBucket: 'gussoni-d3153.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAfVVEKX_ZQ3ItzEcHDvZuX43stykDqf8U',
    appId: '1:362917162978:ios:e7ead42cd3c2a5e32793bb',
    messagingSenderId: '362917162978',
    projectId: 'gussoni-d3153',
    storageBucket: 'gussoni-d3153.firebasestorage.app',
    iosBundleId: 'app.nexora',
  );
}

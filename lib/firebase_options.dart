// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnimplementedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDQKomVXXZXnMVRTYr7Uk4LsJB5Gy3mWME',
    appId: '1:77945139809:android:11aac0260ab9c62eb4b020',
    messagingSenderId: '77945139809',
    projectId: 'worshipflow-df2ce',
    storageBucket: 'worshipflow-df2ce.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCZceXY50a7a6tAvuIfGRwftj-WWSN5ISQ',
    appId: '1:77945139809:ios:a71fab3317caeb98b4b020',
    messagingSenderId: '77945139809',
    projectId: 'worshipflow-df2ce',
    storageBucket: 'worshipflow-df2ce.firebasestorage.app',
    iosBundleId: 'com.example.worshipflow',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCmnJfKBXoS5GMvYoObQMvlUUd2lR7tUwU',
    appId: '1:77945139809:web:dbb4245df0f6a0e2b4b020',
    messagingSenderId: '77945139809',
    projectId: 'worshipflow-df2ce',
    authDomain: 'worshipflow-df2ce.firebaseapp.com',
    storageBucket: 'worshipflow-df2ce.firebasestorage.app',
    measurementId: 'G-W0CRFZBNDD',
  );
}

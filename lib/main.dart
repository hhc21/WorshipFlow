import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  const transportMode = String.fromEnvironment(
    'WF_FIRESTORE_TRANSPORT',
    defaultValue: 'auto',
  );
  final normalizedTransportMode = transportMode.toLowerCase().replaceAll(
    '-',
    '_',
  );
  final useForcedLongPolling =
      kIsWeb && normalizedTransportMode == 'long_polling';
  final firestoreSettings = kIsWeb
      ? Settings(
          persistenceEnabled: true,
          webExperimentalForceLongPolling: useForcedLongPolling,
          webExperimentalAutoDetectLongPolling: !useForcedLongPolling,
          webExperimentalLongPollingOptions: useForcedLongPolling
              ? const WebExperimentalLongPollingOptions(
                  timeoutDuration: Duration(seconds: 20),
                )
              : null,
        )
      : const Settings(persistenceEnabled: true);
  FirebaseFirestore.instance.settings = firestoreSettings;
  runApp(const ProviderScope(child: WorshipFlowApp()));
}

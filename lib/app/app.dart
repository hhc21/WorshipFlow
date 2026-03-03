import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class WorshipFlowApp extends ConsumerWidget {
  const WorshipFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'WorshipFlow',
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}

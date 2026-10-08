import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'router.dart';

void main() => runApp(const ProviderScope(child: WadadakApp()));

class WadadakApp extends ConsumerWidget {
  const WadadakApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: '와다닥',
        theme: WdTheme.light(),
        routerConfig: ref.watch(routerProvider),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart'
    show KakaoSdk;
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'core/config.dart';
import 'core/auth/account_data_cleanup.dart';
import 'features/run/application/run_controller.dart';
import 'core/map/map_view.dart';
import 'core/push/push_service.dart';
import 'push_binding.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  await initMap();
  // 알림을 눌러 앱을 열었을 때 그 알림을 읽으려면 첫 화면 전에 연결한다
  final push = await initPush();
  runApp(
    ProviderScope(
      overrides: [
        pushMessagingProvider.overrideWithValue(push),
        accountDataCleanupProvider.overrideWith(
          (ref) =>
              (owner) =>
                  ref.read(runControllerProvider).purgeWithdrawnOwner(owner),
        ),
      ],
      child: const WadadakApp(),
    ),
  );
}

class WadadakApp extends ConsumerWidget {
  const WadadakApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: '와다닥',
    theme: WdTheme.light(),
    routerConfig: ref.watch(routerProvider),
    builder: (_, child) => PushBinding(child: child ?? const SizedBox.shrink()),
  );
}

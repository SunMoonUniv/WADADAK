import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../routes.dart';

/// 러닝 권한을 위치(필수) → 동작 및 피트니스(선택) 순서로 묻는다.
///
/// 거부해도 다음 화면으로 간다. 위치 권한이 없으면 홈에 들어갈 때 앱 공통 안내가 다시 묻는다(정책 문서 제2부 5장).
class RunPermissions {
  const RunPermissions();

  Future<void> request() async {
    await Permission.locationWhenInUse.request();
    // 걸음 센서: iOS는 동작 및 피트니스(Motion), Android는 신체 활동(ACTIVITY_RECOGNITION).
    await (Platform.isIOS ? Permission.sensors : Permission.activityRecognition).request();
  }
}

final runPermissionsProvider = Provider<RunPermissions>((ref) => const RunPermissions());

/// 권한 안내.
class PermissionScreen extends ConsumerStatefulWidget {
  const PermissionScreen({super.key});

  @override
  ConsumerState<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends ConsumerState<PermissionScreen> {
  bool _requesting = false;

  Future<void> _allow() async {
    setState(() => _requesting = true);
    try {
      await ref.read(runPermissionsProvider).request();
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
    if (mounted) _next();
  }

  void _next() => context.push(Routes.profile);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(WdSpace.s24),
              child: Column(
                spacing: WdSpace.s24,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: WdColors.limeSoft, shape: BoxShape.circle),
                    child: const WdIcon(WdIcons.ghostInfo, size: 32),
                  ),
                  Text(
                    '달리기를 시작하기 전에\n권한을 확인해 주세요',
                    textAlign: TextAlign.center,
                    style: WdText.ko23Bold.copyWith(color: WdColors.ink),
                  ),
                  Text(
                    '러닝 기록과 케이던스 측정에 쓰여요.\n설정에서 언제든 바꿀 수 있어요.',
                    textAlign: TextAlign.center,
                    style: WdText.raw(14, FontWeight.w400, 20).copyWith(color: WdColors.muted),
                  ),
                  const WdSurface(
                    padding: EdgeInsets.symmetric(horizontal: WdSpace.s16, vertical: WdSpace.s4),
                    child: Column(
                      children: [
                        _PermissionRow(
                          icon: WdIcons.locate,
                          title: '위치',
                          required: true,
                          description: '달린 경로를 기록해요. ‘앱을 사용하는 동안’만 허용해도 충분해요.',
                        ),
                        Divider(color: WdColors.divider),
                        _PermissionRow(
                          icon: WdIcons.run,
                          title: '동작 및 피트니스',
                          required: false,
                          description: '걸음 센서로 케이던스(분당 걸음 수)를 측정해요. 허용하지 않아도 달리기는 기록돼요.',
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '‘권한 허용하기’를 누르면 위치 → 동작 및 피트니스 순서로 권한 창이 떠요.',
                    textAlign: TextAlign.center,
                    style: WdText.raw(11, FontWeight.w400).copyWith(color: WdColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.all(WdSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: WdSpace.s12,
            children: [
              WdButton('권한 허용하기', onPressed: _requesting ? null : _allow),
              WdButton('나중에 하기', variant: WdButtonVariant.secondary, onPressed: _requesting ? null : _next),
            ],
          ),
        ),
      );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.icon, required this.title, required this.required, required this.description});

  final WdIcons icon;
  final String title;
  final bool required;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: WdSpace.s14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WdSpace.s12,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: WdColors.limeSoft, shape: BoxShape.circle),
              child: WdIcon(icon, size: 22, color: WdColors.green),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WdSpace.s4,
                children: [
                  Row(
                    spacing: WdSpace.s6,
                    children: [
                      Text(title, style: WdText.raw(15, FontWeight.w700).copyWith(color: WdColors.ink)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: required ? WdColors.ink : WdColors.disabledBg,
                          borderRadius: BorderRadius.circular(WdRadius.full),
                        ),
                        child: Text(
                          required ? '필수' : '선택',
                          style: WdText.raw(10, FontWeight.w700).copyWith(color: required ? WdColors.lime : WdColors.muted),
                        ),
                      ),
                    ],
                  ),
                  Text(description, style: WdText.raw(12, FontWeight.w400).copyWith(color: WdColors.muted)),
                ],
              ),
            ),
          ],
        ),
      );
}

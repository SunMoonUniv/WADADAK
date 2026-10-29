import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/member_api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../routes.dart';
import 'run_history_loader.dart';

/// 내 정보(`GET /members/me`). 다시 로그인하면 새로 받는다. F6에서 저장하면 `ref.invalidate`로 다시 받는다.
final myProfileProvider = FutureProvider<MyProfile>((ref) async {
  // 로그인 상태가 정해질 때까지 기다리고, 로그아웃 뒤 다시 로그인했을 때만 다시 받는다
  await ref.watch(authControllerProvider.selectAsync((auth) => auth is SignedIn));
  return ref.read(memberApiClientProvider).me();
  // 실패하면 저절로 다시 받지 않고 [다시 불러오기]를 보인다
}, retry: (_, _) => null);

/// E3 · 마이페이지 — MY 탭 첫 화면(Figma `E3 · 마이페이지`).
///
/// 위에서부터 프로필(사진 · 닉네임 · 지역 · 소속 · 러닝 경력 · 편집) · 통계(총 거리 · 러닝 · 등록 코스) · 내 활동 메뉴다.
/// - 프로필 아래 줄의 러닝 경력은 가입 때 고른 값이다(`러닝 6개월+`).
/// - 총 거리 · 러닝 횟수는 I1처럼 내 기록을 끝까지 받아 앱이 더한다([AllRunHistory]). 다 받기 전에는 `—`다.
/// - 등록 코스 · 내가 등록한 코스 · 저장한 코스는 코스 쪽 API가 아직 없어 `—`로 자리만 둔다.
/// - 설정(F4) · 편집(F6)도 아직 없어 누르면 준비 중 안내를 띄운다.
/// - 로그아웃은 Figma E3에 없지만 F4 설정이 생길 때까지 맨 아래에 임시로 둔다.
/// (2026-10-29 사용자 결정)
class MyScreen extends ConsumerStatefulWidget {
  const MyScreen({super.key});

  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen> with AllRunHistory {
  void _soon(String name) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$name 화면은 준비 중이에요.')));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WdColors.paper,
    appBar: WdAppBar(
      title: 'MY',
      large: true,
      action: WdAppBarAction.circle(WdIcons.sliders, semanticLabel: '설정', onTap: () => _soon('설정')),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
      children: [
        _Profile(onEdit: () => _soon('프로필 편집')),
        const SizedBox(height: WdSpace.s16),
        ListenableBuilder(
          listenable: runs,
          builder: (context, _) {
            // 끝까지 받기 전이나 받다 실패하면 합계가 덜 나오므로 `—`로 둔다
            final rows = loadingAllRuns || runs.historyNotice != null ? null : allRuns;
            final distance = rows?.fold<double>(0, (sum, row) => sum + row.distanceMeters);
            final count = rows == null ? '—' : '${rows.length}회';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  spacing: WdSpace.s8,
                  children: [
                    _StatTile('총 거리', distance == null ? '—' : _km(distance)),
                    _StatTile('러닝', count),
                    const _StatTile('등록 코스', '—'),
                  ],
                ),
                const SizedBox(height: WdSpace.s16),
                Text('내 활동', style: WdText.ko16Bold.copyWith(color: WdColors.muted)),
                const SizedBox(height: WdSpace.s16),
                WdMenuCard(
                  items: [
                    WdMenuItem(label: '내 러닝 기록', value: count, onTap: () => context.push(Routes.myRecords)),
                    WdMenuItem(label: '내가 등록한 코스', value: '—', onTap: () => _soon('내가 등록한 코스')),
                    WdMenuItem(label: '저장한 코스', value: '—', onTap: () => _soon('저장한 코스')),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: WdSpace.s32),
        // 임시: F4 설정이 생기면 그리로 옮긴다
        WdButton(
          '로그아웃',
          variant: WdButtonVariant.secondary,
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
        ),
      ],
    ),
  );

  /// 100km부터는 정수(Figma `128 km`), 그 아래는 I1처럼 소수 둘째 자리까지.
  static String _km(double meters) {
    final km = meters / 1000;
    return '${km >= 100 ? km.floor() : km.toStringAsFixed(2)} km';
  }
}

/// 사진 · 닉네임 · `지역 · 소속 · 러닝 경력` · [편집].
class _Profile extends ConsumerWidget {
  const _Profile({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    final me = profile.value;
    final url = me?.profileImageUrl;
    return Row(
      spacing: WdSpace.s14,
      children: [
        WdAvatar(size: 64, image: url == null ? null : NetworkImage(url)),
        Expanded(
          child: switch (profile) {
            AsyncData() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WdSpace.s4,
              children: [
                Text(
                  me!.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WdText.raw(20, FontWeight.w700, 25).copyWith(color: WdColors.ink),
                ),
                Text(
                  [
                    me.region?.name,
                    me.affiliation,
                    if (me.runningExperience != null) '러닝 ${me.runningExperience!.label}',
                  ].whereType<String>().where((part) => part.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WdText.body13.copyWith(color: WdColors.muted),
                ),
              ],
            ),
            AsyncError() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('내 정보를 불러오지 못했어요.', style: WdText.body13.copyWith(color: WdColors.muted)),
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  onPressed: () => ref.invalidate(myProfileProvider),
                  child: Text('다시 불러오기', style: WdText.body13Bold.copyWith(color: WdColors.green)),
                ),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
        ),
        Semantics(
          button: true,
          child: InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.all(WdSpace.s4),
              child: Text('편집', style: WdText.body13Bold.copyWith(color: WdColors.green)),
            ),
          ),
        ),
      ],
    );
  }
}

/// 통계 한 칸: 가운데 정렬 라벨 + 굵은 값(Figma E3, 높이 62).
class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: WdSurface(
      height: 62,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 2,
        children: [
          Text(label, style: WdText.raw(11, FontWeight.w400, 14).copyWith(color: WdColors.muted)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WdText.raw(18, FontWeight.w700, 22).copyWith(color: WdColors.ink),
          ),
        ],
      ),
    ),
  );
}

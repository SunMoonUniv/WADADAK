import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/region_api_client.dart';
import '../../core/region_search.dart';
import 'ranking_state.dart';

/// I6 · 지역 선택. 시·군·구를 검색하거나 내 지역 · 최근 선택에서 고르면 보던 지역 랭킹으로 돌아간다.
class RegionSelectScreen extends ConsumerWidget {
  const RegionSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(regionWeeklyProvider(null)).value?.region;
    final recents = ref.watch(recentRegionsProvider);
    final heading = WdText.ko16Bold.copyWith(color: WdColors.muted);

    void pick(Region region) {
      final isMine = region == mine;
      ref.read(selectedRegionProvider.notifier).select(isMine ? null : region);
      if (!isMine) ref.read(recentRegionsProvider.notifier).add(region);
      context.pop();
    }

    WdMenuItem item(Region region, String value) => WdMenuItem(label: region.name, value: value, onTap: () => pick(region));

    return Scaffold(
      appBar: WdAppBar(title: '지역 선택', onBack: () => context.pop()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
        children: [
          RegionSearch(
            onPick: pick,
            idle: [
              if (mine != null) ...[
                Text('내 지역 (기본)', style: heading),
                WdMenuCard(items: [item(mine, '${mine.province} · 활동 지역 ✓')]),
              ],
              if (recents.isNotEmpty) ...[
                Text('최근 선택', style: heading),
                WdMenuCard(items: [for (final region in recents) item(region, region.province)]),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

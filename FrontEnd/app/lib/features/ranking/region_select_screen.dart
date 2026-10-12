import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/ranking_api_client.dart';
import '../../core/error_message.dart';
import 'ranking_state.dart';
import 'ranking_widgets.dart';

/// I6 · 지역 선택. 시·군·구를 검색하거나 내 지역 · 최근 선택에서 고르면 보던 지역 랭킹으로 돌아간다.
class RegionSelectScreen extends ConsumerStatefulWidget {
  const RegionSelectScreen({super.key});

  @override
  ConsumerState<RegionSelectScreen> createState() => _RegionSelectScreenState();
}

class _RegionSelectScreenState extends ConsumerState<RegionSelectScreen> {
  Timer? _debounce;
  var _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// 입력이 0.3초 멈추면 찾는다.
  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = text.trim()));
  }

  void _pick(Region region, Region? mine) {
    final isMine = region == mine;
    ref.read(selectedRegionProvider.notifier).select(isMine ? null : region);
    if (!isMine) ref.read(recentRegionsProvider.notifier).add(region);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(regionWeeklyProvider(null)).value?.region;
    final recents = ref.watch(recentRegionsProvider);
    final heading = WdText.ko16Bold.copyWith(color: WdColors.muted);
    final muted = WdText.raw(14, FontWeight.w400, 20).copyWith(color: WdColors.muted);
    WdMenuItem item(Region region, String value) =>
        WdMenuItem(label: region.name, value: value, onTap: () => _pick(region, mine));

    return Scaffold(
      appBar: WdAppBar(title: '지역 선택', onBack: () => context.pop()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WdSpace.s16,
            children: [
              WdTextField(
                soft: true,
                hintText: '시 · 군 · 구 이름 검색',
                maxLength: 20,
                textInputAction: TextInputAction.search,
                onChanged: _search,
              ),
              if (_query.isNotEmpty)
                switch (ref.watch(regionSearchProvider(_query))) {
                  AsyncValue(value: final regions?) when regions.isEmpty => Text('찾는 지역이 없어요', style: muted),
                  AsyncValue(value: final regions?) =>
                    WdMenuCard(items: [for (final region in regions) item(region, province(region))]),
                  AsyncValue(:final error?) => Text(errorMessage(error), style: muted),
                  _ => const RankingLoading(),
                }
              else ...[
                if (mine != null) ...[
                  Text('내 지역 (기본)', style: heading),
                  WdMenuCard(items: [item(mine, '${province(mine)} · 활동 지역 ✓')]),
                ],
                if (recents.isNotEmpty) ...[
                  Text('최근 선택', style: heading),
                  WdMenuCard(items: [for (final region in recents) item(region, province(region))]),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'api/region_api_client.dart';
import 'error_message.dart';

/// 실패하면 다시 받지 않는다. 검색어를 바꾸면 새로 찾는다.
final regionSearchProvider = FutureProvider.autoDispose.family<List<Region>, String>(
  (ref, query) => ref.watch(regionApiClientProvider).search(query),
  retry: (_, _) => null,
);

/// 시·군·구 검색 칸과 결과(I6 디자인). 입력이 0.3초 멈추면 찾고, 결과를 누르면 [onPick]을 부른다.
/// 검색어가 없을 때는 [idle]을 보인다(I6: 내 지역 · 최근 선택).
class RegionSearch extends ConsumerStatefulWidget {
  const RegionSearch({super.key, required this.onPick, this.idle = const []});

  final ValueChanged<Region> onPick;
  final List<Widget> idle;

  @override
  ConsumerState<RegionSearch> createState() => _RegionSearchState();
}

class _RegionSearchState extends ConsumerState<RegionSearch> {
  Timer? _debounce;
  var _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final muted = WdText.raw(14, FontWeight.w400, 20).copyWith(color: WdColors.muted);
    return Column(
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
        if (_query.isEmpty)
          ...widget.idle
        else
          switch (ref.watch(regionSearchProvider(_query))) {
            AsyncValue(value: final regions?) when regions.isEmpty => Text('찾는 지역이 없어요', style: muted),
            AsyncValue(value: final regions?) => WdMenuCard(items: [
                for (final region in regions)
                  WdMenuItem(label: region.name, value: region.province, onTap: () => widget.onPick(region)),
              ]),
            AsyncValue(:final error?) => Text(errorMessage(error), style: muted),
            _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: WdSpace.s24),
                child: Center(child: CircularProgressIndicator(color: WdColors.ink)),
              ),
          },
      ],
    );
  }
}

/// 활동 지역 고르기(가입 프로필 F2). 로그인 전에도 쓴다.
class RegionPickScreen extends StatelessWidget {
  const RegionPickScreen({super.key});

  /// 고른 지역을 돌려준다. 고르지 않고 돌아가면 null.
  static Future<Region?> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegionPickScreen()));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: WdAppBar(title: '활동 지역', onBack: () => Navigator.pop(context)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
          children: [RegionSearch(onPick: (region) => Navigator.pop(context, region))],
        ),
      );
}

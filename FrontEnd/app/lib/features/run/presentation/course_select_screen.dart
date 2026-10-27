import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/course_api_client.dart';
import '../../../core/api/ranking_api_client.dart';
import '../../../core/map/geo_point.dart';
import '../../../routes.dart';
import '../../course/course_format.dart';
import '../../course/course_list_card.dart';
import '../../course/detail/course_ranking_state.dart';
import '../../home/my_location.dart';
import '../../review/review_state.dart';
import '../application/course_run_entry.dart';
import '../application/run_controller.dart';
import '../domain/course_run.dart';
import '../domain/run_models.dart';
import 'course_prep_view.dart';

enum _Source { recent, nearby }

/// 내 주변: 현재 위치에서 가까운 코스(약 3km 안). 위치 권한이 없으면 빈 목록
final _nearbyProvider = FutureProvider.autoDispose<List<CourseListItem>>((
  ref,
) async {
  final here = await ref.watch(myLocationProvider).ifAllowed();
  if (here == null) return const [];
  const d = 0.03;
  final page = await ref
      .watch(courseApiClientProvider)
      .listCourses(
        southWest: GeoPoint(here.lat - d, here.lng - d),
        northEast: GeoPoint(here.lat + d, here.lng + d),
        sort: CourseListSort.nearest,
        origin: here,
      );
  return page.courses;
}, retry: (_, _) => null);

final _searchProvider = FutureProvider.autoDispose
    .family<List<CourseListItem>, String>(
      (ref, query) async =>
          (await ref.watch(courseApiClientProvider).searchCourses(query: query))
              .courses,
      retry: (_, _) => null,
    );

/// C8 코스 선택 (달리기 준비, Figma 1453:4434). 고르면 C6로 돌아가 그 코스로 달린다. 코스 없이 달리면 자유 러닝(RUN-03)
class CourseSelectScreen extends ConsumerStatefulWidget {
  const CourseSelectScreen({super.key});

  @override
  ConsumerState<CourseSelectScreen> createState() => _CourseSelectScreenState();
}

class _CourseSelectScreenState extends ConsumerState<CourseSelectScreen> {
  static const _page = 3;
  _Source _source = _Source.recent;
  String _query = '';
  CourseSelection? _picked;
  int _shown = _page;

  void _show(_Source source) => setState(() {
    _source = source;
    _shown = _page;
  });

  void _notReady(String what) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$what은 준비 중이에요.')));

  @override
  Widget build(BuildContext context) {
    final searching = CourseApiClient.isSearchable(_query);
    // 최근 달린 코스: 내 기록 목록(RecordSummary.course)에서 최근 것부터, 같은 코스는 한 번
    final runs = ref.watch(runControllerProvider);
    return ListenableBuilder(
      listenable: runs,
      builder: (context, _) {
        final List<({String id, String name, CourseListItem? item})> courses =
            searching
            ? [
                for (final c
                    in ref.watch(_searchProvider(_query.trim())).value ??
                        const <CourseListItem>[])
                  (id: c.courseId, name: c.name, item: c),
              ]
            : switch (_source) {
                _Source.recent => recentCourses(runs.remoteRecords),
                _Source.nearby => [
                  for (final c
                      in ref.watch(_nearbyProvider).value ??
                          const <CourseListItem>[])
                    (id: c.courseId, name: c.name, item: c),
                ],
              };
        final visible = courses.take(_shown).toList();
        return Scaffold(
          backgroundColor: WdColors.paper,
          appBar: WdAppBar(
            title: '코스 선택',
            onBack: () => context.pop(),
            action: WdAppBarAction.button(
              '지도에서 찾기',
              onTap: () => context.go(Routes.home),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              WdSpace.s24,
              WdSpace.s20,
              WdSpace.s24,
              WdSpace.s24,
            ),
            children: [
              WdSearchBar(
                hintText: '코스 이름 검색',
                onChanged: (value) => setState(() {
                  _query = value;
                  _shown = _page;
                }),
              ),
              const SizedBox(height: WdSpace.s16),
              Wrap(
                spacing: WdSpace.s6,
                children: [
                  WdFilterChip(
                    '최근 달린',
                    selected: !searching && _source == _Source.recent,
                    height: 36,
                    onTap: () => _show(_Source.recent),
                  ),
                  WdFilterChip(
                    '저장한 코스',
                    height: 36,
                    onTap: () => _notReady('저장한 코스'),
                  ),
                  WdFilterChip(
                    '내 주변',
                    selected: !searching && _source == _Source.nearby,
                    height: 36,
                    onTap: () => _show(_Source.nearby),
                  ),
                  WdFilterChip(
                    '내가 만든',
                    height: 36,
                    onTap: () => _notReady('내가 만든 코스'),
                  ),
                ],
              ),
              const SizedBox(height: WdSpace.s16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      searching
                          ? '검색 결과'
                          : (_source == _Source.recent
                                ? '최근 달린 코스'
                                : '내 주변 코스'),
                      style: WdText.ko16Bold.copyWith(color: WdColors.muted),
                    ),
                  ),
                  Text(
                    '코스를 골라 주세요',
                    style: WdText.ko12.copyWith(color: WdColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: WdSpace.s16),
              if (courses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: WdSpace.s24),
                  child: Text(
                    searching
                        ? '찾는 코스가 없어요.'
                        : _source == _Source.recent
                        ? '아직 달린 코스가 없어요. 내 주변이나 검색으로 골라 보세요.'
                        : '가까운 코스가 없거나 위치를 확인할 수 없어요.',
                    textAlign: TextAlign.center,
                    style: WdText.ko12.copyWith(color: WdColors.muted),
                  ),
                ),
              for (final c in visible) ...[
                _PickCard(
                  courseId: c.id,
                  name: c.name,
                  item: c.item,
                  picked: _picked?.courseId == c.id,
                  onTap: () =>
                      setState(() => _picked = CourseSelection(c.id, c.name)),
                ),
                const SizedBox(height: WdSpace.s12),
              ],
              if (courses.length > visible.length)
                WdButton(
                  '코스 ${courses.length - visible.length}개 더 보기',
                  variant: WdButtonVariant.secondary,
                  onPressed: () => setState(() => _shown += 6),
                ),
              const SizedBox(height: WdSpace.s12),
              const WdInfoBanner('코스를 고르지 않으면 자유 러닝으로 달려요.', plain: true),
            ],
          ),
          bottomNavigationBar: WdBottomBar.dual(
            secondary: WdButton(
              '코스 없이 달리기',
              variant: WdButtonVariant.secondary,
              onPressed: () {
                ref.read(runControllerProvider).clearCourse();
                ref.read(courseTabProvider.notifier).set(false);
                ref.read(ghostTabProvider.notifier).set(false);
                context.pop();
              },
            ),
            primary: WdButton(
              '이 코스로 설정',
              onPressed: _picked == null
                  ? null
                  : () {
                      ref.read(selectedCourseProvider.notifier).select(_picked);
                      context.pop();
                    },
            ),
          ),
        );
      },
    );
  }
}

/// 내 기록 목록(RecordSummary, 최근 것부터)의 코스 요약에서 최근 달린 코스. 같은 코스는 한 번
List<({String id, String name, CourseListItem? item})> recentCourses(
  List<Map<String, dynamic>> records,
) {
  final seen = <String>{};
  return [
    for (final record in records)
      if (record['course'] case {
        'courseId': final String id,
        'courseName': final String name,
      })
        if (seen.add(id)) (id: id, name: name, item: null),
  ];
}

/// Figma C8 코스 카드: 선택 원 · 경로 썸네일 · 이름 · 거리·난이도·평점 · 내 최고 기록·순위 · 현재 러너/만료 임박
class _PickCard extends ConsumerWidget {
  const _PickCard({
    required this.courseId,
    required this.name,
    required this.item,
    required this.picked,
    required this.onTap,
  });
  final String courseId, name;

  /// 목록 API 값(내 주변·검색). 최근 달린 코스는 없어서 상세를 받는다
  final CourseListItem? item;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = item == null
        ? ref.watch(runCourseDetailProvider(courseId)).value
        : null;
    final rating =
        item?.averageRating ??
        (item == null
            ? ref.watch(reviewSummaryProvider(courseId)).value?.averageRating
            : null);
    final distance = item?.distanceMeters ?? detail?.distanceMeters;
    final difficulty = item?.difficulty ?? detail?.difficulty;
    final route = item?.route ?? detail?.route;
    final expiresAt = item?.expiresAt ?? detail?.expiresAt;
    final runners = item?.activeRunners ?? detail?.activeRunners ?? 0;
    final me = ref
        .watch(
          courseRankingProvider((
            courseId: courseId,
            period: RankingPeriod.all,
          )),
        )
        .value;
    final best = me?.me.courseElapsedSeconds;
    final daysLeft = expiresAt == null
        ? null
        : daysUntilExpiry(expiresAt, DateTime.now());
    return Semantics(
      button: true,
      selected: picked,
      child: WdSurface(
        padding: const EdgeInsets.all(WdSpace.s14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WdSpace.s10,
          children: [
            Row(
              spacing: WdSpace.s12,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: picked ? WdColors.ink : WdColors.white,
                    border: Border.all(
                      color: picked ? WdColors.ink : WdColors.disabledBg,
                    ),
                  ),
                ),
                WdRouteThumbnail(
                  width: 50,
                  height: 50,
                  child: route == null ? null : CourseRouteThumbnail(route),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: WdSpace.s3,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WdText.ko16Bold,
                      ),
                      Text(
                        [
                          if (distance != null) formatKm(distance),
                          if (difficulty != null) '난이도 ${difficulty.label}',
                          if (rating != null) '★ ${rating.toStringAsFixed(1)}',
                        ].join(' · '),
                        style: WdText.ko12.copyWith(color: WdColors.muted),
                      ),
                      Text(
                        best == null
                            ? '아직 달린 기록 없음'
                            : [
                                '내 최고 ${formatRunTime(Duration(seconds: best))}',
                                if (me!.me.status == MyRankStatus.ranked)
                                  '${me.me.rank}위 / ${formatCount(me.participantCount)}명',
                              ].join(' · '),
                        style: WdText.ko12.copyWith(color: WdColors.green),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (daysLeft != null && daysLeft <= 7) // 만료 임박(정책 공통: D-7 ~ D-0)
              Text(
                formatExpiry(daysLeft),
                style: WdText.ko12.copyWith(color: WdColors.warning),
              )
            else
              Text(
                formatActiveRunners(runners),
                style: WdText.ko12.copyWith(color: WdColors.green),
              ),
          ],
        ),
      ),
    );
  }
}

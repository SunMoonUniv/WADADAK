import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/course_api_client.dart';
import '../../../routes.dart';
import '../../run/application/run_controller.dart';
import '../../run/domain/run_models.dart';
import '../course_format.dart';
import '../course_list_card.dart';
import '../course_public_period_sheet.dart';
import 'record_select_rows.dart';

/// B6 · 내 기록에서 코스 등록(Figma 1453:4060). B5 `내 기록에서 코스 올리기`에서 연다. 하단 탭을 덮는다.
///
/// - 기록은 I1과 같다(달리기 담당 `runController`의 기기 기록 + 서버 기록). 거리순은 앱에서 늘어놓으므로 끝까지 50개씩 받는다.
/// - 등록할 수 없는 기록도 사유와 함께 흐리게 보인다(B6-04). 안내 · 탭 · 정렬 칩 · 카드는 4.1 `B6 화면` · `B6 카드`.
/// - 등록 가능한 기록을 누르면 오늘 한도를 다시 보고 B11 → D4로 간다(B6-03 · B6-06).
/// - 카드 썸네일은 서버 기록 요약의 달린 경로 선이다. 경로가 없는 기록(예전 기록 · 동기화 대기)은 지도색 빈 칸이다(4.1 `B6 카드 경로 그림`).
class RecordSelectScreen extends ConsumerStatefulWidget {
  const RecordSelectScreen({super.key, this.now = DateTime.now});

  /// 오늘. 카드 날짜에 해를 붙일지 정한다. 테스트에서 고정한다.
  final DateTime Function() now;

  /// 위 안내(B6-01). Figma 문구에 등록 조건을 더했다.
  static const guide = '코스로 등록할 기록을 골라 주세요. 1 km 이상 달리고 GPS 신호가 좋았던, 아직 등록하지 않은 기록만 '
      '등록할 수 있어요. 거리 상한은 없고, 하루 3개까지 등록할 수 있어요.';

  /// 누른 사이 다른 기기 등에서 그 기록으로 코스를 등록했다(결과 화면 카드 · D4와 같은 말).
  static const usedMessage = '이미 코스로 등록한 기록이에요.';

  @override
  ConsumerState<RecordSelectScreen> createState() => _RecordSelectScreenState();
}

class _RecordSelectScreenState extends ConsumerState<RecordSelectScreen> {
  /// 한 번에 받는 기록 수(서버 최대). 끝까지 받으므로 클수록 요청이 적다(I1과 같다).
  static const _pageSize = 50;

  /// Figma B6 비활성 카드.
  static const _disabledOpacity = 0.55;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  late final RunController _runs;
  var _sort = RecordSort.recent;

  /// 이 화면이 부른 첫 기록 받기가 끝났다. 그 전에는 다른 화면(I1)이 받아 둔 목록이 남아 있을 수 있다.
  var _started = false;

  /// 오늘 등록 한도와 GPS 코스 등록에 쓴 기록. 받지 못하면 null이고 막지 않는다(D4 등록 때 서버가 다시 본다).
  RegistrationQuota? _quota;

  /// 카드를 눌러 한도를 확인하거나 B11 · D4가 떠 있다. 두 번 눌러 두 번 열지 않는다.
  var _opening = false;

  /// 카드를 눌러 한도를 다시 받는 중이다. 위에 진행 막대를 보이고 다른 카드는 누를 수 없다(4.1 B6-03 · B6-06).
  var _checking = false;

  @override
  void initState() {
    super.initState();
    _runs = ref.read(runControllerProvider)..addListener(_loadRest);
    unawaited(_loadQuota());
    Future.microtask(() async {
      await _runs.bindOwner();
      if (!mounted) return;
      await _runs.loadHistory(pageSize: _pageSize);
      if (!mounted) return;
      setState(() => _started = true);
      _loadRest();
    });
  }

  @override
  void dispose() {
    _runs.removeListener(_loadRest);
    super.dispose();
  }

  /// 한 페이지를 받을 때마다 다음 페이지를 이어 받는다. 실패하면 멈추고 안내로 다시 받게 한다.
  void _loadRest() {
    if (!mounted || !_started || _runs.loadingHistory || _runs.nextCursor == null || _runs.historyNotice != null) {
      return;
    }
    unawaited(_runs.loadHistory(more: true, pageSize: _pageSize));
  }

  /// 한도 요청 번호. 늦게 온 옛 응답이 새 응답을 덮지 않게 마지막 요청의 응답만 화면에 쓴다.
  var _quotaRequest = 0;

  /// 받지 못하면(응답을 읽지 못한 경우 포함) null이고 막지 않는다(D4 등록 때 서버가 다시 본다).
  Future<RegistrationQuota?> _loadQuota() async {
    final request = ++_quotaRequest;
    try {
      final quota = await ref.read(courseApiClientProvider).registrationQuota();
      if (mounted && request == _quotaRequest) setState(() => _quota = quota);
      return quota;
    } on Object {
      return null;
    }
  }

  Future<void> _refresh() async {
    await _runs.sync(manual: true);
    // 올리는 사이 화면을 닫았으면 더 받지 않는다
    if (!mounted) return;
    await Future.wait([_runs.loadHistory(pageSize: _pageSize), _loadQuota()]);
  }

  /// 등록 가능한 기록을 골랐다. 한도를 다시 보고 B11을 띄운 뒤 `확인`이면 D4로 간다.
  Future<void> _pick(RecordChoice record) async {
    if (_opening) return;
    _opening = true;
    setState(() => _checking = true);
    try {
      final quota = await _loadQuota();
      if (!mounted) return;
      setState(() => _checking = false);
      if (quota != null && quota.gps.remaining <= 0) return _notify(gpsQuotaUsedUpMessage);
      if (quota != null && quota.usedRunRecordIds.contains(record.id)) return _notify(RecordSelectScreen.usedMessage);
      if (!await showCoursePublicPeriodSheet(context) || !mounted) return;
      await context.push(Routes.gpsCourseInfo(record.id));
      // D4에서 돌아왔다(등록하면 홈으로 가서 여기 오지 않는다)
      if (mounted) unawaited(_loadQuota());
    } finally {
      _opening = false;
    }
  }

  void _notify(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// `09.03 (목)`. 올해 기록이 아니면 해를 붙인다. 한국 시간이다(코스 날짜 표시와 같다).
  String _title(DateTime startedAt) {
    final seoul = startedAt.toUtc().add(const Duration(hours: 9));
    final thisYear = widget.now().toUtc().add(const Duration(hours: 9)).year;
    final day = seoul.year == thisYear ? formatMonthDay(startedAt) : '${seoul.year}.${formatMonthDay(startedAt)}';
    return '$day (${_weekdays[seoul.weekday - 1]})';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _runs,
    builder: (context, _) {
      final rows = recordChoices(local: _runs.records, remote: _runs.remoteRecords, deletedIds: _runs.deletedIds)
        ..sort(_sort.compare);
      final used = {...?_quota?.usedRunRecordIds};
      final statuses = [for (final r in rows) statusOf(r, used)];
      // 끝까지 받기 전에는 순서 · 개수가 바뀌므로 로딩으로 보인다
      final loading =
          !_started || _runs.historyNotice == null && (_runs.nextCursor != null || _runs.loadingHistory);
      final quotaUsedUp = (_quota?.gps.remaining ?? 1) <= 0;
      final header = [
        const WdInfoBanner(RecordSelectScreen.guide, plain: true),
        if (quotaUsedUp) ...[
          const SizedBox(height: WdSpace.s8),
          const WdInfoBanner(gpsQuotaUsedUpMessage, tone: WdBannerTone.warning),
        ],
        const SizedBox(height: WdSpace.s16),
        Row(
          spacing: WdSpace.s6,
          children: [
            WdFilterChip(
              RecordSort.recent.label,
              selected: _sort == RecordSort.recent,
              height: 36,
              onTap: () => setState(() => _sort = RecordSort.recent),
            ),
            WdFilterChip(
              _sort == RecordSort.recent ? RecordSort.longest.label : _sort.label,
              selected: _sort != RecordSort.recent,
              height: 36,
              onTap: () => setState(() => _sort = _sort.distanceTapped),
            ),
          ],
        ),
        const SizedBox(height: WdSpace.s16),
        Text(
          loading ? '등록 가능한 기록' : '등록 가능한 기록 ${statuses.where((s) => s == RecordStatus.registrable).length}',
          style: WdText.ko16Bold.copyWith(color: WdColors.muted),
        ),
        if (_runs.historyNotice != null) ...[
          const SizedBox(height: WdSpace.s8),
          const WdInfoBanner('서버 기록을 불러오지 못했어요. 기기에 저장된 기록은 볼 수 있어요.', tone: WdBannerTone.warning),
          TextButton(
            onPressed: _runs.loadingHistory
                ? null
                : () => _runs.loadHistory(more: _runs.nextCursor != null, pageSize: _pageSize),
            child: const Text('다시 불러오기'),
          ),
        ],
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: WdSpace.s32),
            child: Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(color: WdColors.ink, strokeWidth: 2),
              ),
            ),
          )
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WdSpace.s32),
            child: Text(
              '아직 달린 기록이 없어요.',
              textAlign: TextAlign.center,
              style: WdText.label12.copyWith(color: WdColors.muted),
            ),
          ),
      ];
      final cards = loading ? 0 : rows.length;
      return DefaultTabController(
        length: 1,
        child: Scaffold(
          backgroundColor: WdColors.paper,
          appBar: WdAppBar(title: '내 기록에서 등록', onBack: () => context.pop()),
          body: Column(
            children: [
              // 기록 유형은 거르지 않는다. I1처럼 탭을 두되 `전체` 하나다(4.1 B6 화면)
              const DecoratedBox(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: WdColors.map))),
                child: WdTabBar(tabs: ['전체']),
              ),
              SizedBox(
                height: 2,
                child: _checking
                    ? const LinearProgressIndicator(color: WdColors.ink, backgroundColor: WdColors.map, minHeight: 2)
                    : null,
              ),
              Expanded(
                child: AbsorbPointer(
                  absorbing: _checking,
                  child: RefreshIndicator(
                    color: WdColors.ink,
                    onRefresh: _refresh,
                    // 기록을 끝까지 받으므로 보이는 카드만 그린다
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
                      itemCount: header.length + cards,
                      itemBuilder: (context, i) => i < header.length
                          ? header[i]
                          : Padding(
                              padding: const EdgeInsets.only(top: WdSpace.s16),
                              child: _card(rows[i - header.length], statuses[i - header.length]),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _card(RecordChoice record, RecordStatus status) {
    final enabled = status == RecordStatus.registrable;
    final card = WdRunRecordCard.selectable(
      title: _title(record.startedAt),
      summary:
          // 버림이라 1 km 미만 기록이 `1.00 km`로 보이지 않는다(formatKm과 같다)
          '${(record.distanceMeters ~/ 10 / 100).toStringAsFixed(2)} km · ${formatRunTime(record.elapsed)} · '
          '${formatRunPace(record.paceSecondsPerKm)}/km',
      thumbnail: CourseRouteThumbnail.segments(record.route),
      tags: [
        WdTag(record.typeLabel, filled: false),
        WdTag(
          status.label,
          tone: switch (status) {
            RecordStatus.registrable => WdTone.success,
            RecordStatus.pendingSync => WdTone.warning,
            _ => WdTone.neutral,
          },
          filled: false,
        ),
      ],
      onTap: enabled ? () => _pick(record) : null,
    );
    return enabled ? card : Semantics(enabled: false, child: Opacity(opacity: _disabledOpacity, child: card));
  }
}

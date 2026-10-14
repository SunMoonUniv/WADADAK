import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/run_models.dart';
import 'free_run_live_view.dart';
import 'run_lap_list.dart';

/// Figma 1731:5635 — 자유 러닝 결과. 원본 ms의 두 시간 값을 그대로 표시한다.
class FreeRunResultView extends StatelessWidget {
  const FreeRunResultView({
    super.key,
    required this.run,
    required this.onConfirm,
    this.onDelete,
    this.history = false,
  });
  final RunSnapshot run;
  final VoidCallback onConfirm;
  final VoidCallback? onDelete;
  final bool history;

  @override
  Widget build(BuildContext context) {
    final start = run.startedAt?.toLocal();
    final startedLabel = start == null
        ? '—'
        : '${start.year}.${_two(start.month)}.${_two(start.day)} · ${_two(start.hour)}:${_two(start.minute)} 시작';
    final speed = run.hasLocation && run.movingTime.inMilliseconds > 0
        ? '${(run.distanceMeters * 3600 / run.movingTime.inMilliseconds).toStringAsFixed(1)} km/h'
        : '—';
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(
        title: '러닝 결과',
        onBack: onConfirm,
        action: WdAppBarAction.icon(
          WdIcons.share,
          semanticLabel: '러닝 결과 공유',
          onTap: () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('결과 공유 기능은 준비 중이에요.'))),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 208),
              color: WdColors.lime,
              padding: const EdgeInsets.all(WdSpace.s24),
              child: Column(
                spacing: WdSpace.s12,
                children: [
                  WdSurface(
                    color: WdColors.ink,
                    radius: WdRadius.full,
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: WdSpace.s8),
                    child: Text(
                      '러닝 완료 · ${run.storageStatus}',
                      style: WdText.ko12Medium.copyWith(color: WdColors.lime),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      runDistance(run),
                      style: WdText.run56W800H74.copyWith(color: WdColors.ink),
                    ),
                  ),
                  Text(
                    '오늘도 한 걸음 더 달렸어요.',
                    style: WdText.ko22Bold.copyWith(color: WdColors.ink),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(WdSpace.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WdSpace.s20,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: WdSpace.s3,
                    children: [
                      Text('자유 러닝', style: WdText.ko16Bold),
                      Text(
                        startedLabel,
                        style: WdText.ko12.copyWith(color: WdColors.muted),
                      ),
                    ],
                  ),
                  WdSurface(
                    radius: WdRadius.r12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: WdSpace.s14,
                      vertical: WdSpace.s12,
                    ),
                    child: Row(
                      spacing: WdSpace.s10,
                      children: [
                        const WdIcon(WdIcons.ghostInfo, size: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: WdSpace.s2,
                            children: [
                              Text('코스 등록 준비 중이에요', style: WdText.run13W700H16),
                              Text(
                                'GPS 경로 수집 후 사용할 수 있어요',
                                style: WdText.ko12.copyWith(
                                  color: WdColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  WdSurface(
                    padding: const EdgeInsets.all(WdSpace.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: WdSpace.s8,
                      children: [
                        Row(
                          spacing: WdSpace.s24,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _resultMetric(
                                '총 소요 시간 (기록)',
                                formatRunTime(run.elapsed),
                              ),
                            ),
                            Expanded(
                              child: _resultMetric(
                                '평균 페이스',
                                formatRunPace(run.paceSecondsPerKm),
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: WdSpace.s8,
                          children: [
                            Text(
                              '이동 시간 ${formatRunTime(run.movingTime)}',
                              style: WdText.ko11.copyWith(
                                color: WdColors.muted,
                              ),
                            ),
                            Text(
                              '달린 시간 ${formatRunTime(run.active)}',
                              style: WdText.ko11.copyWith(
                                color: WdColors.muted,
                              ),
                            ),
                            Text(
                              '일시정지 ${formatRunTime(run.elapsed - run.active)}',
                              style: WdText.ko11.copyWith(
                                color: WdColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _RunStatSummary([
                    ('평균 속도', speed),
                    (
                      '케이던스',
                      run.averageCadence == null
                          ? '—'
                          : '${run.averageCadence!.round()} spm',
                    ),
                    ('소모 칼로리', '—'),
                  ]),
                  if (run.averageCadence != null &&
                      run.cadenceCoverageMs < run.active.inMilliseconds)
                    const WdInfoBanner(
                      '걸음 센서가 측정되지 않은 구간이 있어요. 평균 케이던스는 측정된 구간만 사용해요.',
                      tone: WdBannerTone.warning,
                    ),
                  if (run.averageCadence == null)
                    const Text('케이던스 측정 데이터가 없어요.'),
                  const _RunStatSummary([
                    ('상승 고도', '—'),
                    ('최고 구간', '—'),
                    ('최고 페이스', '—'),
                  ]),
                  _RunStatSummary([
                    ('이동시간', formatRunTime(run.movingTime)),
                    ('총 페이스', formatRunPace(run.elapsedPaceSecondsPerKm)),
                    ('정지시간', formatRunTime(run.elapsed - run.movingTime)),
                  ]),
                  Text(
                    '평균 페이스는 이동시간, 총 페이스는 정지를 포함한 총 시간 기준이에요.',
                    style: WdText.ko12.copyWith(color: WdColors.muted),
                  ),
                  SizedBox(height: 180, child: RunRouteView(run: run)),
                  if (run.gapCount > 0)
                    WdInfoBanner(
                      'GPS 측정 공백 ${run.gapCount}곳의 확인하지 못한 거리는 포함하지 않았어요.',
                      tone: WdBannerTone.warning,
                    ),
                  if (run.endReason != null && run.endReason != 'USER')
                    const WdInfoBanner(
                      '측정이 중단되어 마지막 저장 지점까지 기록했어요.',
                      tone: WdBannerTone.warning,
                    ),
                  RunLapList(run: run),
                  WdInfoBanner(
                    run.storageStatus == '기기 저장' ||
                            run.storageStatus.startsWith('기기 저장 ·')
                        ? '이 기기에 기록을 저장했어요. 서버 등록을 기다리고 있어요.'
                        : run.storageStatus == '측정 거리 없음'
                        ? '측정된 거리가 없어 개인 기록을 저장하지 않았어요.'
                        : run.storageStatus == '저장 전'
                        ? '러닝 기록을 확인해 주세요.'
                        : '기기와 서버에 기록을 저장했어요.',
                    tone: WdBannerTone.warning,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: history
          ? WdBottomBar.dual(
              secondary: WdButton(
                '기록 삭제',
                onPressed: onDelete,
                variant: WdButtonVariant.secondary,
              ),
              primary: WdButton('확인', onPressed: onConfirm),
            )
          : WdBottomBar.pinned(primary: WdButton('확인', onPressed: onConfirm)),
    );
  }

  Widget _resultMetric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: WdSpace.s8,
    children: [
      Text(label, style: WdText.ko12.copyWith(color: WdColors.muted)),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: WdText.run34W700H39.copyWith(color: WdColors.ink),
        ),
      ),
    ],
  );

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _RunStatSummary extends StatelessWidget {
  const _RunStatSummary(this.items);
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: WdSpace.s8,
    children: [
      for (final (label, value) in items)
        Expanded(
          child: WdSurface(
            padding: const EdgeInsets.all(WdSpace.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: WdSpace.s6,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: WdText.ko12.copyWith(color: WdColors.muted),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: WdText.numeric24.copyWith(color: WdColors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

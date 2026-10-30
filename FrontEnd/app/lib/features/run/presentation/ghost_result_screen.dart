import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/run_models.dart';
import 'run_segment_analysis_screen.dart';

/// D2: server verdict and comparison times. Unavailable source metrics are not estimated.
class GhostResultScreen extends StatelessWidget {
  const GhostResultScreen({super.key, required this.run});
  final RunSnapshot run;

  @override
  Widget build(BuildContext context) {
    final result = run.ghost!;
    final ours = (result['courseElapsedSeconds'] as num).toInt();
    final theirs = (result['sourceElapsedSeconds'] as num).toInt();
    final valid = result['outcome'] != 'INVALID';
    final title = switch (result['outcome']) {
      'WIN' => '승리',
      'LOSE' => '패배',
      'DRAW' => '무승부',
      _ => '대결 무효',
    };
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(title: '대결 결과', onBack: () => Navigator.pop(context)),
      body: ListView(
        children: [
          Container(
            color: WdColors.lime,
            padding: const EdgeInsets.all(24),
            child: Column(
              spacing: 12,
              children: [
                WdSurface(
                  color: WdColors.ink,
                  radius: WdRadius.full,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    title,
                    style: WdText.ko12Medium.copyWith(color: WdColors.lime),
                  ),
                ),
                Text(
                  valid ? '${(theirs - ours).abs()} 초' : '—',
                  style: WdText.run56W800H74,
                ),
                Text(
                  switch (result['outcome']) {
                    'WIN' => '고스트보다 빨랐어요.',
                    'LOSE' => '다음 대결을 향해 한 걸음 더.',
                    'DRAW' => '같은 시간에 도착했어요.',
                    _ => '완주 조건을 충족하지 못했어요.',
                  },
                  style: WdText.ko22Bold,
                  textAlign: TextAlign.center,
                ),
                Text(
                  '상대 ${formatRunTime(Duration(seconds: theirs))}',
                  style: WdText.ko12.copyWith(color: WdColors.green),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                Text(run.course?.courseName ?? '자유 러닝', style: WdText.ko16Bold),
                WdSurface(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(child: _time('나의 기록', ours, WdColors.ink)),
                      Expanded(child: _time('고스트 기록', theirs, WdColors.muted)),
                    ],
                  ),
                ),
                const Text('기록 비교', style: WdText.ko14Bold),
                WdSurface(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    spacing: 12,
                    children: [
                      for (final row in [
                        ('항목', '나', '고스트'),
                        (
                          '대결 비교 시간',
                          formatRunTime(Duration(seconds: ours)),
                          formatRunTime(Duration(seconds: theirs)),
                        ),
                        ('달린 시간', formatRunTime(run.active), '—'),
                        ('평균 페이스', formatRunPace(run.paceSecondsPerKm), '—'),
                        (
                          '평균 케이던스',
                          run.averageCadence == null
                              ? '—'
                              : '${run.averageCadence!.round()} spm',
                          '—',
                        ),
                        (
                          '최고 구간',
                          run.resultStats?.bestLapNumber == null
                              ? '—'
                              : '${run.resultStats!.bestLapNumber}구간',
                          '—',
                        ),
                      ])
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(row.$1, style: WdText.ko12),
                            ),
                            Expanded(
                              child: Text(
                                row.$2,
                                textAlign: TextAlign.right,
                                style: WdText.ko12Medium,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                row.$3,
                                textAlign: TextAlign.right,
                                style: WdText.ko12.copyWith(
                                  color: WdColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const Text('정지를 포함한 동일 경로 비교 시간', style: WdText.ko12),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: WdBottomBar.dual(
        secondary: WdButton(
          '구간 상세',
          variant: WdButtonVariant.secondary,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RunSegmentAnalysisScreen(run: run),
            ),
          ),
        ),
        primary: WdButton('확인', onPressed: () => Navigator.pop(context)),
      ),
    );
  }

  Widget _time(String label, int seconds, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Text(label, style: WdText.ko12.copyWith(color: WdColors.muted)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          formatRunTime(Duration(seconds: seconds)),
          style: WdText.run34W700H39.copyWith(color: color),
        ),
      ),
    ],
  );
}

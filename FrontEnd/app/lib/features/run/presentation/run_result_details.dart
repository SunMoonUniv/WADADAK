import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/run_models.dart';
import 'run_lap_list.dart';

/// Explanations and secondary measurements live in D3 rather than crowding D1.
class RunResultDetails extends StatelessWidget {
  const RunResultDetails({super.key, required this.run});
  final RunSnapshot run;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: WdSpace.s12,
    children: [
      WdStatSummary([
        ('이동시간', formatRunTime(run.movingTime)),
        ('총 페이스', formatRunPace(run.elapsedPaceSecondsPerKm)),
        ('정지시간', formatRunTime(run.elapsed - run.movingTime)),
      ]),
      Text(
        '평균 페이스는 이동시간, 총 페이스는 정지를 포함한 총 시간 기준이에요.',
        style: WdText.ko12.copyWith(color: WdColors.muted),
      ),
      const Text(
        '최고 구간은 완주한 1km 랩, 최고 페이스는 연속 30초 평균 기준이에요.',
        style: WdText.ko12,
      ),
      if (run.resultStats?.bestLapPaceSecondsPerKm != null)
        Text(
          '최고 구간 페이스 ${formatRunPace(run.resultStats!.bestLapPaceSecondsPerKm)}/km',
          style: WdText.ko12,
        ),
      if (run.resultStats?.bestPaceSecondsPerKm != null)
        Text(
          '최고 페이스 ${formatRunPace(run.resultStats!.bestPaceSecondsPerKm)}',
          style: WdText.ko12,
        ),
      if (run.resultStats == null)
        const Text('이 기록의 상세 지표를 계산할 원본 데이터가 없어요.', style: WdText.ko12),
      if (run.resultStats != null && run.resultStats!.bestLapNumber == null)
        Text(
          run.distanceMeters < 1000
              ? '최고 구간은 1km 완주 후 표시돼요.'
              : 'GPS 공백 없는 완성된 1km 랩이 없어 최고 구간을 표시할 수 없어요.',
          style: WdText.ko12,
        ),
      if (run.resultStats != null &&
          run.resultStats!.bestPaceSecondsPerKm == null)
        const Text('최고 페이스를 계산할 연속 30초 이동 기록이 없어요.', style: WdText.ko12),
      if (run.resultStats != null && run.resultStats!.elevationGainM == null)
        const Text('상승 고도를 계산할 고도 측정 데이터가 없어요.', style: WdText.ko12),
      if (run.resultStats?.elevationSource == 'BAROMETER' ||
          run.resultStats?.elevationSource == 'MIXED')
        Text(
          run.resultStats!.elevationSource == 'BAROMETER'
              ? '기압 센서로 측정한 상승 고도예요.'
              : '구간별로 기압 센서와 GPS 고도를 사용했어요.',
          style: WdText.ko12,
        ),
      if (run.resultStats?.elevationPartial == true)
        const WdInfoBanner(
          '상승 고도는 고도가 측정된 일부 구간만 포함해요.',
          tone: WdBannerTone.warning,
        ),
      if (run.averageCadence == null)
        const Text('케이던스 측정 데이터가 없어요.', style: WdText.ko12)
      else if (run.cadenceCoverageMs < run.active.inMilliseconds)
        const WdInfoBanner(
          '걸음 센서가 측정되지 않은 구간이 있어요. 평균 케이던스는 측정된 구간만 사용해요.',
          tone: WdBannerTone.warning,
        ),
      RunLapList(run: run),
    ],
  );
}

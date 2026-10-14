import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/run_models.dart';

class RunLapList extends StatelessWidget {
  const RunLapList({
    super.key,
    required this.run,
    this.dark = false,
    this.recentOnly = false,
  });
  final RunSnapshot run;
  final bool dark, recentOnly;
  @override
  Widget build(BuildContext context) {
    final all = run.laps;
    final laps = recentOnly && all.length > 4
        ? all.sublist(all.length - 4)
        : all;
    final ink = dark ? WdColors.white : WdColors.ink;
    final sub = dark ? WdColors.runTextSub : WdColors.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('랩 기록', style: WdText.ko14Bold.copyWith(color: ink)),
            ),
            Text('1 km 자동', style: WdText.ko12.copyWith(color: sub)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final label in ['구간', '이동 시간', '평균 페이스'])
              Expanded(
                child: Text(label, style: WdText.ko11.copyWith(color: sub)),
              ),
          ],
        ),
        for (final lap in laps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    lap.complete
                        ? '${lap.number} km'
                        : '${run.state == RunState.finished ? '마지막' : '현재'} ${(lap.distanceM / 1000).toStringAsFixed(2)} km',
                    style: WdText.ko12.copyWith(
                      color: lap.complete ? sub : (dark ? WdColors.lime : ink),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    formatRunTime(Duration(milliseconds: lap.movingMs)),
                    style: WdText.ko13.copyWith(color: ink),
                  ),
                ),
                Expanded(
                  child: Text(
                    formatRunPace(lap.paceSecondsPerKm),
                    style: WdText.ko13.copyWith(color: ink),
                  ),
                ),
              ],
            ),
          ),
        if (laps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              run.state == RunState.finished
                  ? '측정된 구간이 없어요.'
                  : '첫 구간을 측정하고 있어요.',
              style: WdText.ko12.copyWith(color: sub),
            ),
          ),
        if (run.state != RunState.finished)
          Text(
            '현재 ${all.where((l) => l.complete).length + 1}랩 · ${(run.distanceMeters % 1000 / 1000).toStringAsFixed(2)} km',
            style: WdText.ko12.copyWith(color: sub),
          ),
      ],
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/run_models.dart';

/// D1: completed kilometre laps only. Partial laps remain in the analysis view.
class RunPaceBars extends StatelessWidget {
  const RunPaceBars({super.key, required this.run});
  final RunSnapshot run;

  @override
  Widget build(BuildContext context) {
    final laps = run.laps
        .where((l) => l.complete && l.paceSecondsPerKm != null)
        .toList();
    final paces = laps.map((l) => l.paceSecondsPerKm!).toList();
    final fastest = paces.isEmpty ? 0.0 : paces.reduce(math.min);
    final slowest = paces.isEmpty ? 0.0 : paces.reduce(math.max);
    final best =
        run.resultStats?.bestLapNumber ??
        (laps.isEmpty ? null : laps[paces.indexOf(fastest)].number);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WdSpace.s8,
      children: [
        Row(
          children: [
            const Expanded(child: Text('구간 페이스', style: WdText.ko14Bold)),
            Text('1 km 단위', style: WdText.ko12.copyWith(color: WdColors.muted)),
          ],
        ),
        WdSurface(
          radius: WdRadius.r12,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: laps.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: WdSpace.s24),
                  child: Text(
                    '완성된 1km 구간이 없어요.',
                    style: WdText.ko12.copyWith(color: WdColors.muted),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = math.max(
                      constraints.maxWidth,
                      laps.length * 58.0,
                    );
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          spacing: WdSpace.s10,
                          children: [
                            for (var i = 0; i < laps.length; i++)
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: WdSpace.s6,
                                  children: [
                                    Text(
                                      formatRunPace(paces[i]),
                                      maxLines: 1,
                                      style: WdText.ko12.copyWith(
                                        color: laps[i].number == best
                                            ? WdColors.green
                                            : WdColors.muted,
                                      ),
                                    ),
                                    Container(
                                      width: 28,
                                      height: slowest == fastest
                                          ? 119
                                          : 49 +
                                                70 *
                                                    (slowest - paces[i]) /
                                                    (slowest - fastest),
                                      decoration: BoxDecoration(
                                        color: laps[i].number == best
                                            ? WdColors.lime
                                            : const Color(0xFFCDD5C6),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(6),
                                            ),
                                      ),
                                    ),
                                    Text(
                                      '${laps[i].number} km',
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
                    );
                  },
                ),
        ),
      ],
    );
  }
}

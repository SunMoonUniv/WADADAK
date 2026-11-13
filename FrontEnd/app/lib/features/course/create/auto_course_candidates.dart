part of 'auto_course_view.dart';

/// A3 후보. 지도에 후보를 모두 그리고 고른 후보를 라임 선으로 강조한다. 카드 · 지도 번호를 누르면 고른다.
class _CandidatesView extends StatefulWidget {
  const _CandidatesView({required this.form, required this.result, required this.onRetry, required this.onPick});

  final PlanForm form;
  final PlanResult result;
  final VoidCallback onRetry;
  final ValueChanged<List<GeoPoint>> onPick;

  @override
  State<_CandidatesView> createState() => _CandidatesViewState();
}

class _CandidatesViewState extends State<_CandidatesView> {
  var _selected = 0;

  List<PlanCandidate> get _candidates => widget.result.candidates;

  @override
  Widget build(BuildContext context) {
    final notApplied = widget.result.notApplied;
    return Column(
      children: [
        SizedBox(height: 268, child: _map()),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s16, WdSpace.s24, WdSpace.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WdSpace.s10,
              children: [
                Text(planSummary(widget.form, startName: widget.result.startName),
                    style: WdText.body13Medium.copyWith(color: WdColors.ink)),
                for (final (i, candidate) in _candidates.indexed)
                  _CandidateCard(
                    number: i + 1,
                    candidate: candidate,
                    shape: widget.form.shape!,
                    prefer: widget.form.prefer,
                    selected: i == _selected,
                    onTap: () => setState(() => _selected = i),
                  ),
                if (notApplied.isNotEmpty)
                  WdInfoBanner('${[for (final pref in notApplied) pref.label].join(' · ')} 조건은 아직 반영하지 않았어요.',
                      tone: WdBannerTone.warning),
              ],
            ),
          ),
        ),
        WdBottomBar.dual(
          secondary: WdButton('다시 찾기', variant: WdButtonVariant.secondary, onPressed: widget.onRetry),
          primary: WdButton('이 코스로 만들기', onPressed: () => widget.onPick(_candidates[_selected].anchorPoints)),
        ),
      ],
    );
  }

  Widget _map() {
    final start = _candidates.first.anchorPoints.first;
    return Stack(
      children: [
        MapView(
          initialCenter: start,
          initialZoom: 14,
          onCreated: (map) => map.fitPoints([for (final candidate in _candidates) ...candidate.anchorPoints]),
          lines: [
            for (final (i, candidate) in _candidates.indexed)
              MapLine(
                id: 'plan-$i',
                points: candidate.anchorPoints,
                style: i == _selected ? MapLineStyle.course : MapLineStyle.candidate,
              ),
          ],
          markers: [
            MapMarker(
              id: 'plan-start',
              position: start,
              child: const WdRouteEndpoint.start(),
              imageKey: 'route-start',
              anchor: WdRouteEndpoint.startAnchor,
              priority: 1,
            ),
            for (final (i, candidate) in _candidates.indexed)
              MapMarker(
                id: 'plan-number-$i',
                position: _farthest(candidate.anchorPoints),
                child: _NumberBadge(i + 1, selected: i == _selected),
                imageKey: 'plan-number-${i + 1}-${i == _selected}',
                priority: i == _selected ? 3 : 2,
                onTap: () => setState(() => _selected = i),
              ),
          ],
        ),
        // OSM 데이터로 만든 경로라 출처를 보인다(정책 B3-A07).
        Positioned(
          right: WdSpace.s8,
          bottom: WdSpace.s8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: WdSpace.s6, vertical: WdSpace.s2),
            decoration: BoxDecoration(color: WdColors.paper, borderRadius: BorderRadius.circular(4)),
            child: Text('© OpenStreetMap contributors', style: WdText.micro10.copyWith(color: WdColors.muted)),
          ),
        ),
      ],
    );
  }

  /// 번호표 자리: 출발점에서 가장 먼 점. 후보마다 다른 방향이라 번호가 잘 겹치지 않는다.
  static GeoPoint _farthest(List<GeoPoint> points) =>
      points.reduce((a, b) => points.first.distanceTo(b) > points.first.distanceTo(a) ? b : a);
}

/// 지도 위 후보 번호(Figma A3 `후보 N · 번호`). 고른 후보는 라임 바탕.
class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.number, {required this.selected});

  final int number;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? WdColors.lime : WdColors.paper,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? WdColors.ink : WdColors.ghost, width: 1.5),
        ),
        child: Text('$number', style: WdText.body13Bold.copyWith(color: selected ? WdColors.ink : WdColors.muted)),
      );
}

/// 후보 카드(Figma AI / Candidate card). 예: `5.14km · 한 바퀴 · 오르막 32m` / `큰길 24% · 편의점 3곳 · 같은 길 2%`.
/// 오르막은 서버가 알 때만 보인다. 화장실 수와 인도 · 강변 · 밝은 길 비율은 그 조건을 골랐을 때만, 둘째 줄 앞에 보인다
/// (둘째 줄이 넘치면 뒤가 잘린다).
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.number,
    required this.candidate,
    required this.shape,
    required this.prefer,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final PlanCandidate candidate;
  final PlanShape shape;
  final Set<PlanPref> prefer;
  final bool selected;
  final VoidCallback onTap;

  static String _percent(double ratio) => '${(ratio * 100).round()}%';

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 72,
            padding: const EdgeInsets.fromLTRB(WdSpace.s14, WdSpace.s14, WdSpace.s16, WdSpace.s14),
            decoration: BoxDecoration(
              color: selected ? WdColors.limeSoft : WdColors.paper,
              borderRadius: BorderRadius.circular(WdRadius.r16),
              border: Border.all(color: selected ? WdColors.ink : WdColors.line, width: selected ? 1.5 : 1),
            ),
            child: Row(
              spacing: WdSpace.s12,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: selected ? WdColors.lime : WdColors.soft, shape: BoxShape.circle),
                  child: Text('$number',
                      style: WdText.body13Bold.copyWith(color: selected ? WdColors.ink : WdColors.muted)),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                          [
                            '${(candidate.distanceMeters / 1000).toStringAsFixed(2)}km',
                            shape.label,
                            if (candidate.ascentMeters case final ascent?) '오르막 ${ascent}m',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WdText.cardTitle14.copyWith(color: WdColors.ink)),
                      Text(
                        [
                          if (prefer.contains(PlanPref.river) && candidate.riverRatio != null)
                            '강변 ${_percent(candidate.riverRatio!)}',
                          if (prefer.contains(PlanPref.sidewalk) && candidate.sidewalkRatio != null)
                            '인도 ${_percent(candidate.sidewalkRatio!)}',
                          if (prefer.contains(PlanPref.lit) && candidate.litRatio != null)
                            '밝은 길 ${_percent(candidate.litRatio!)}',
                          if (prefer.contains(PlanPref.toiletOnRoute)) '화장실 ${candidate.toiletCount}곳',
                          '큰길 ${_percent(candidate.arterialRatio)}',
                          '편의점 ${candidate.storeCount}곳',
                          '같은 길 ${_percent(candidate.retraceRatio)}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WdText.label12.copyWith(color: WdColors.muted),
                      ),
                    ],
                  ),
                ),
                if (selected) const WdIcon(WdIcons.check, size: 24, color: WdColors.ink),
              ],
            ),
          ),
        ),
      );
}

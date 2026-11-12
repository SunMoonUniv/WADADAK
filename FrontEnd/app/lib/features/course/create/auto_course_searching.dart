part of 'auto_course_view.dart';

/// A2 찾는 중. 서버가 단계를 알려 주지 않아 시간에 따라 단계를 넘긴다(출발지 찾기 → 후보 만들기 → 고르기).
class _SearchingView extends StatefulWidget {
  const _SearchingView({required this.form, this.request});

  final PlanForm form;
  final String? request;

  static const steps = ['출발지 찾기', '길 따라 후보 만들기', '서로 다른 3개 고르기'];

  @override
  State<_SearchingView> createState() => _SearchingViewState();
}

class _SearchingViewState extends State<_SearchingView> {
  var _step = 0;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _timers.addAll([
      Timer(const Duration(milliseconds: 800), () => setState(() => _step = 1)),
      Timer(const Duration(seconds: 4), () => setState(() => _step = 2)),
    ]);
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WdSpace.s16,
                children: [
                  PlanRequestBubble(widget.request ?? planSummary(widget.form)),
                  Container(
                    padding: const EdgeInsets.all(WdSpace.s20),
                    decoration: BoxDecoration(color: WdColors.soft, borderRadius: BorderRadius.circular(WdRadius.r16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: WdSpace.s12,
                      children: [
                        Text('코스를 찾고 있어요', style: WdText.title17.copyWith(color: WdColors.ink)),
                        Text('길을 따라 후보를 만들고, 서로 겹치지 않는 코스를 고르는 중이에요.',
                            style: WdText.body13.copyWith(color: WdColors.muted)),
                        WdProgressBar(value: const [0.2, 0.58, 0.85][_step]),
                        for (final (i, label) in _SearchingView.steps.indexed)
                          _ProgressStep(label, done: i < _step, active: i == _step),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(WdSpace.s24, 0, WdSpace.s24, WdSpace.s24),
              child: Column(
                spacing: WdSpace.s16,
                children: [
                  Text('보통 몇 초 안에 끝나요.', style: WdText.label12.copyWith(color: WdColors.muted)),
                  const WdButton('코스 찾는 중…', onPressed: null),
                ],
              ),
            ),
          ),
        ],
      );
}

/// 찾는 단계 한 줄(Figma AI / Progress step: Done · Active · Pending).
class _ProgressStep extends StatelessWidget {
  const _ProgressStep(this.label, {required this.done, required this.active});

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 24,
        child: Row(
          spacing: WdSpace.s10,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? WdColors.lime : (active ? WdColors.limeSoft : WdColors.paper),
                border: Border.all(
                  color: done || active ? WdColors.ink : WdColors.line,
                  width: active ? 2 : 1,
                ),
              ),
              child: done ? const WdIcon(WdIcons.check, size: 12, color: WdColors.ink) : null,
            ),
            Expanded(
              child: Text(
                label,
                style: (done || active ? WdText.raw(14, FontWeight.w500, 20) : WdText.run14W400H20)
                    .copyWith(color: done || active ? WdColors.ink : WdColors.muted),
              ),
            ),
          ],
        ),
      );
}

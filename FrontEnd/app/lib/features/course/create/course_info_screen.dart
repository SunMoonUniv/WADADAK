import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/error_message.dart';
import '../../../core/map/map_view.dart';
import '../course_format.dart';

/// B4 코스 정보 입력 & 등록.
///
/// 위 지도에는 서버가 만든 최종 경로와 1km 거리 표지만 보인다(B4-01). 입력점은 보이지 않는다.
/// 등록 성공 팝업을 닫으면 등록한 코스를 결과로 돌려주며 닫힌다. B3가 그 결과로 홈에 돌아간다(B4-07).
class CourseInfoScreen extends ConsumerStatefulWidget {
  const CourseInfoScreen({super.key, required this.route});

  final GeneratedRoute route;

  @override
  ConsumerState<CourseInfoScreen> createState() => _CourseInfoScreenState();
}

class _CourseInfoScreenState extends ConsumerState<CourseInfoScreen> {
  // Figma 코스 지도 카드(A / Course map) 높이.
  static const _mapHeight = 110.0;
  static const _nameMaxLength = 50;
  static final _spaces = RegExp(r'\s+');

  final _name = TextEditingController();
  Timer? _nameCheck;

  /// 서버가 이미 있다고 알려 준 이름. 이름을 고치면 다시 확인한다.
  String? _takenName;

  Difficulty? _difficulty;
  final _tags = <CourseTag>{};

  /// 오늘 사용자 지정 코스를 더 등록할 수 없다(등록 응답 COURSE-008).
  var _quotaUsedUp = false;
  var _submitting = false;

  /// 이 화면에서 하는 등록 하나의 멱등 키. 실패 뒤 다시 보낼 때도 같은 값을 쓴다(STA-05).
  final _idempotencyKey = const Uuid().v4();

  @override
  void dispose() {
    _nameCheck?.cancel();
    _name.dispose();
    super.dispose();
  }

  /// 서버와 같이 정리한 이름: 앞뒤 공백 제거, 연속 공백 한 칸.
  String get _nameValue => _name.text.trim().replaceAll(_spaces, ' ');

  /// 이름 안내(B4-02). 비어 있으면 없다.
  String? get _nameProblem {
    final name = _nameValue;
    if (name.isEmpty) return null;
    // 서버처럼 코드 포인트로 센다.
    final length = name.runes.length;
    if (length < 2) return '2자 이상 입력해 주세요';
    if (length > _nameMaxLength) return '$_nameMaxLength자까지 입력할 수 있어요';
    if (name == _takenName) return '이미 있는 코스 이름이에요';
    return null;
  }

  bool get _canRegister =>
      _nameValue.isNotEmpty && _nameProblem == null && _difficulty != null && !_quotaUsedUp && !_submitting;

  /// 입력이 멈추면 같은 이름이 있는지 확인한다.
  void _onNameChanged(String _) {
    _nameCheck?.cancel();
    setState(() {});
    final name = _nameValue;
    if (name.isEmpty || _nameProblem != null) return;
    _nameCheck = Timer(const Duration(milliseconds: 300), () => _checkName(name));
  }

  Future<void> _checkName(String name) async {
    try {
      final available = await ref.read(courseApiClientProvider).isNameAvailable(name);
      if (mounted && !available) setState(() => _takenName = name);
    } on ApiException {
      // 막지 않는다. 등록할 때 서버가 다시 확인한다.
    }
  }

  void _toggleTag(CourseTag tag) => setState(() => _tags.contains(tag) ? _tags.remove(tag) : _tags.add(tag));

  /// 실패하면 입력을 그대로 두고 알린다(STA-05).
  Future<void> _register() async {
    _nameCheck?.cancel();
    setState(() => _submitting = true);
    try {
      final course = await ref.read(courseApiClientProvider).registerCustom(
            idempotencyKey: _idempotencyKey,
            anchorPoints: widget.route.anchorPoints,
            name: _nameValue,
            difficulty: _difficulty!,
            tags: _tags,
          );
      if (!mounted) return;
      await _showRegistered();
      if (mounted) context.pop(course);
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'COURSE-006':
          setState(() => _takenName = _nameValue);
        case 'COURSE-008':
          setState(() => _quotaUsedUp = true);
          showError(context, e);
        // 경로 때문에 막혔다. 다시 보내도 같아서 이유만 알린다. 경로는 B3로 돌아가 고친다.
        case 'COURSE-003' || 'COURSE-004' || 'COURSE-005' || 'COURSE-007' || 'COURSE-009':
          showError(context, e);
        default:
          showError(context, e, onRetry: _register);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showRegistered() => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('코스를 등록했어요'),
          content: const Text('바로 공개돼서 다른 러너도 달릴 수 있어요.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final label = WdText.ko16Bold.copyWith(color: WdColors.muted);
    final nameProblem = _nameProblem;
    return PopScope(
      // 등록하는 동안은 나가지 않는다. 결과를 놓치면 다시 등록하다 오늘 한도에 걸린다.
      canPop: !_submitting,
      child: Scaffold(
        // 경로를 고치려면 B3로 돌아간다. B3에는 입력점이 그대로 있다.
        appBar: WdAppBar(
          title: '코스 정보',
          onBack: () {
            if (!_submitting) context.pop();
          },
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WdSpace.s16,
              children: [
                _map(),
                Text('코스 이름', style: label),
                WdTextField(
                  soft: true,
                  controller: _name,
                  hintText: '코스 이름을 입력하세요',
                  maxLength: _nameMaxLength,
                  textInputAction: TextInputAction.done,
                  onChanged: _onNameChanged,
                ),
                if (nameProblem != null) Text(nameProblem, style: WdText.ko12.copyWith(color: WdColors.warningText)),
                Text('난이도', style: label),
                Row(
                  spacing: WdSpace.s6,
                  children: [
                    for (final difficulty in Difficulty.values)
                      WdFilterChip(
                        difficulty.label,
                        height: 36,
                        selected: _difficulty == difficulty,
                        onTap: () => setState(() => _difficulty = difficulty),
                      ),
                  ],
                ),
                Text('코스 특징 (중복 선택)', style: label),
                // Figma처럼 네 개씩 두 줄.
                for (final row in [CourseTag.values.sublist(0, 4), CourseTag.values.sublist(4)])
                  Row(
                    spacing: WdSpace.s6,
                    children: [
                      for (final tag in row)
                        WdFilterChip(tag.label, height: 36, selected: _tags.contains(tag), onTap: () => _toggleTag(tag)),
                    ],
                  ),
                Text('코스 유형', style: label),
                // 실제 완주 판정(달리기 정책 5.3)은 서버가 한다. 이탈 안내 수치는 완주 기준이 아니라 적지 않는다.
                const WdSurface(
                  padding: EdgeInsets.all(WdSpace.s14),
                  child: WdStepRow(title: '그려서 만든 코스', description: '경로를 따라 끝까지 달려야 완주로 기록돼요.'),
                ),
                const WdInfoBanner(
                  '등록한 날부터 30일 동안 공개돼요. 그 안에 누군가 완주하면 30일 연장되고, 기간이 끝나면 비공개로 바뀐 뒤 24시간 후 삭제돼요.',
                  plain: true,
                ),
                if (_quotaUsedUp) const WdInfoBanner(customQuotaUsedUpMessage, tone: WdBannerTone.warning),
              ],
            ),
          ],
        ),
        bottomNavigationBar: WdBottomBar.pinned(
          primary: WdButton('코스 등록하기', onPressed: _canRegister ? _register : null),
        ),
      ),
    );
  }

  Widget _map() => ClipRRect(
        borderRadius: BorderRadius.circular(WdRadius.r12),
        child: SizedBox(
          height: _mapHeight,
          child: MapView(
            initialCenter: widget.route.route.first,
            lines: [MapLine(id: 'route', points: widget.route.route)],
            markers: [
              for (final marker in widget.route.distanceMarkers)
                MapMarker(
                  id: 'km-${marker.km}',
                  position: marker.point,
                  child: WdKmMarker('${marker.km} km'),
                  imageKey: 'km:${marker.km}',
                ),
            ],
            onCreated: (map) => map.fitPoints(widget.route.route),
          ),
        ),
      );
}

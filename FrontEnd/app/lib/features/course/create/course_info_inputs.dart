import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/map/map_view.dart';

/// 코스 정보 입력(B4 · D4)이 같이 쓰는 입력: 이름(B4-02) · 난이도(B4-03) · 특징(B4-04).
mixin CourseInfoInputs<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  static const nameMaxLength = 50;
  static final _spaces = RegExp(r'\s+');

  final nameController = TextEditingController();
  Timer? _nameCheck;

  /// 서버가 이미 있다고 알려 준 이름. 이름을 고치면 다시 확인한다.
  String? _takenName;

  Difficulty? difficulty;
  final tags = <CourseTag>{};

  @override
  void dispose() {
    _nameCheck?.cancel();
    nameController.dispose();
    super.dispose();
  }

  /// 서버와 같이 정리한 이름: 앞뒤 공백 제거, 연속 공백 한 칸.
  String get nameValue => nameController.text.trim().replaceAll(_spaces, ' ');

  /// 이름 안내(B4-02). 비어 있으면 없다.
  String? get nameProblem {
    final name = nameValue;
    if (name.isEmpty) return null;
    // 서버처럼 코드 포인트로 센다.
    final length = name.runes.length;
    if (length < 2) return '2자 이상 입력해 주세요';
    if (length > nameMaxLength) return '$nameMaxLength자까지 입력할 수 있어요';
    if (name == _takenName) return '이미 있는 코스 이름이에요';
    return null;
  }

  /// 이름 · 난이도를 다 넣었다. 특징은 고르지 않아도 된다.
  bool get inputsReady => nameValue.isNotEmpty && nameProblem == null && difficulty != null;

  /// 등록 응답이 이미 있는 이름이라고 했다(COURSE-006).
  void markNameTaken() => setState(() => _takenName = nameValue);

  /// 등록을 보내기 전에 부른다. 기다리던 이름 확인을 그만둔다.
  void stopNameCheck() => _nameCheck?.cancel();

  /// 입력이 멈추면 같은 이름이 있는지 확인한다.
  void _onNameChanged(String _) {
    _nameCheck?.cancel();
    setState(() {});
    final name = nameValue;
    if (name.isEmpty || nameProblem != null) return;
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

  /// 이름 칸과 그 아래 안내. 바깥 [Column]의 간격으로 띄운다.
  List<Widget> nameInputs() {
    final problem = nameProblem;
    return [
      WdTextField(
        soft: true,
        controller: nameController,
        hintText: '코스 이름을 입력하세요',
        maxLength: nameMaxLength,
        textInputAction: TextInputAction.done,
        onChanged: _onNameChanged,
      ),
      if (problem != null) Text(problem, style: WdText.ko12.copyWith(color: WdColors.warningText)),
    ];
  }

  /// 난이도 하나만 고른다.
  Widget difficultyChips() => Row(
        spacing: WdSpace.s6,
        children: [
          for (final value in Difficulty.values)
            WdFilterChip(
              value.label,
              height: 36,
              selected: difficulty == value,
              onTap: () => setState(() => difficulty = value),
            ),
        ],
      );

  /// 특징 여러 개. Figma B4처럼 네 개씩 두 줄이다.
  List<Widget> tagChipRows() => [
        for (final row in [CourseTag.values.sublist(0, 4), CourseTag.values.sublist(4)])
          Row(
            spacing: WdSpace.s6,
            children: [
              for (final tag in row)
                WdFilterChip(tag.label, height: 36, selected: tags.contains(tag), onTap: () => _toggleTag(tag)),
            ],
          ),
      ];

  void _toggleTag(CourseTag tag) => setState(() => tags.contains(tag) ? tags.remove(tag) : tags.add(tag));
}

/// 코스 공개 기간 안내(B4-05 · D4). 정책 공통 4를 줄였다.
const coursePublicPeriodNotice =
    '등록한 날부터 30일 동안 공개돼요. 그 안에 누군가 완주하면 30일 연장되고, 기간이 끝나면 비공개로 바뀐 뒤 24시간 후 삭제돼요.';

/// 등록 성공 팝업(B4-07 · D4). `확인`을 누르면 닫힌다.
Future<void> showCourseRegistered(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('코스를 등록했어요'),
        content: const Text('바로 공개돼서 다른 러너도 달릴 수 있어요.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
      ),
    );

/// 서버가 만든 최종 경로와 1km 거리 표지만 보이는 지도(B4-01 · D4). 크기는 감싸는 쪽이 정한다.
class CourseRouteMap extends StatelessWidget {
  const CourseRouteMap({super.key, required this.route, required this.distanceMarkers});

  final List<GeoPoint> route;
  final List<DistanceMarker> distanceMarkers;

  @override
  Widget build(BuildContext context) => MapView(
        initialCenter: route.first,
        lines: [MapLine(id: 'route', points: route)],
        markers: [
          for (final marker in distanceMarkers)
            MapMarker(
              id: 'km-${marker.km}',
              position: marker.point,
              child: WdKmMarker('${marker.km} km'),
              imageKey: 'km:${marker.km}',
            ),
        ],
        onCreated: (map) => map.fitPoints(route),
      );
}

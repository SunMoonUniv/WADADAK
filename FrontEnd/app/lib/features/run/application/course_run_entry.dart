import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routes.dart';
import '../domain/course_run.dart';

/// 코스 상세에서 고른 코스. 달리기 컨트롤러가 받아 가고 비운다(`runControllerProvider`).
final selectedCourseProvider =
    NotifierProvider<SelectedCourse, CourseSelection?>(SelectedCourse.new);

class SelectedCourse extends Notifier<CourseSelection?> {
  @override
  CourseSelection? build() => null;

  void select(CourseSelection? course) => state = course;
}

/// 달리기 준비에서 `코스 러닝` 탭을 골랐다(C6). 코스를 아직 안 골라도 C6를 보이고, 코스는 C8에서 고른다
final courseTabProvider = NotifierProvider<CourseTab, bool>(CourseTab.new);

class CourseTab extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool course) => state = course;
}

/// 개인 기록 고스트 준비. 공개 랭킹의 자동 상대 선택과 별도 진입점이다(공통 6).
final ghostTabProvider = NotifierProvider<GhostTab, bool>(GhostTab.new);

class GhostTab extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool ghost) => state = ghost;
}

/// 코스 상세(B1 · B9 · G3)의 `이 코스로 달리기`. 코스를 고르고 달리기 탭으로 간다.
/// 진행 중인 러닝이 있으면 코스를 바꾸지 않고 그 러닝 화면을 보인다(RUN-05).
void runCourse(BuildContext context, WidgetRef ref, CourseSelection course) {
  ref.read(selectedCourseProvider.notifier).select(course);
  ref.read(courseTabProvider.notifier).set(true);
  ref.read(ghostTabProvider.notifier).set(false);
  GoRouter.maybeOf(context)?.go(Routes.run);
}

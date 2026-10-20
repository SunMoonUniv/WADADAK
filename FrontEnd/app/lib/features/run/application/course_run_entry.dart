import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routes.dart';
import '../domain/course_run.dart';

/// 코스 상세에서 고른 코스. 달리기 컨트롤러가 받아 가고 비운다(`runControllerProvider`).
final selectedCourseProvider = NotifierProvider<SelectedCourse, CourseSelection?>(SelectedCourse.new);

class SelectedCourse extends Notifier<CourseSelection?> {
  @override
  CourseSelection? build() => null;

  void select(CourseSelection? course) => state = course;
}

/// 코스 상세(B1 · B9 · G3)의 `이 코스로 달리기`. 코스를 고르고 달리기 탭으로 간다.
/// 진행 중인 러닝이 있으면 코스를 바꾸지 않고 그 러닝 화면을 보인다(RUN-05).
void runCourse(BuildContext context, WidgetRef ref, CourseSelection course) {
  ref.read(selectedCourseProvider.notifier).select(course);
  GoRouter.maybeOf(context)?.go(Routes.run);
}

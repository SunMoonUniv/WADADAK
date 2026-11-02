import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/course_api_client.dart';
import '../../core/api/member_api_client.dart';
import '../../core/api/ranking_api_client.dart';

/// 실패하면 다시 받지 않고 화면이 다시 시도를 보인다.
Duration? _noRetry(int _, Object _) => null;

/// I3 위쪽 프로필. 탈퇴했거나 없는 회원이면 MEMBER-011.
final runnerProfileProvider = FutureProvider.autoDispose.family<RunnerProfile, String>(
  (ref, memberId) => ref.watch(memberApiClientProvider).runnerProfile(memberId),
  retry: _noRetry,
);

/// I3 `총 거리` · `러닝`.
final runnerDistanceProvider = FutureProvider.autoDispose.family<MemberDistanceTotal, String>(
  (ref, memberId) => ref.watch(rankingApiClientProvider).memberDistanceTotal(memberId),
  retry: _noRetry,
);

/// I3 `등록 코스 N개`.
final runnerCourseCountProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, memberId) => ref.watch(courseApiClientProvider).runnerCourseCount(memberId),
  retry: _noRetry,
);

typedef RunnerRecordKey = ({String courseId, String memberId, RankingPeriod period});

/// I3 `이 코스에서의 기록`. 그 러너가 그 기간 순위에 없으면 null이고 섹션을 통째로 숨긴다.
final runnerRecordProvider = FutureProvider.autoDispose.family<RunnerCourseRecord?, RunnerRecordKey>(
  (ref, key) => ref.watch(rankingApiClientProvider).runnerCourseRecord(key.courseId, key.memberId, key.period),
  retry: _noRetry,
);

/// I3 `등록한 코스`. 첫 쪽을 받고 [RunnerCoursesNotifier.loadMore]로 이어 받는다.
final runnerCoursesProvider =
    AsyncNotifierProvider.autoDispose.family<RunnerCoursesNotifier, RunnerCoursePage, String>(
  RunnerCoursesNotifier.new,
  retry: _noRetry,
);

class RunnerCoursesNotifier extends AsyncNotifier<RunnerCoursePage> {
  RunnerCoursesNotifier(this.memberId);

  final String memberId;
  bool _loading = false;

  @override
  Future<RunnerCoursePage> build() => ref.watch(courseApiClientProvider).runnerCourses(memberId);

  /// 다음 쪽을 붙인다. 실패하면 받아 둔 코스는 그대로 두고 오류를 던진다.
  Future<void> loadMore() async {
    final page = state.value;
    if (page == null || page.nextCursor == null || _loading) return;
    _loading = true;
    try {
      final next = await ref.read(courseApiClientProvider).runnerCourses(memberId, cursor: page.nextCursor);
      // 받는 사이에 새로고침했으면 버린다.
      if (ref.mounted && identical(state.value, page)) {
        state = AsyncData((courses: [...page.courses, ...next.courses], nextCursor: next.nextCursor));
      }
    } finally {
      _loading = false;
    }
  }
}

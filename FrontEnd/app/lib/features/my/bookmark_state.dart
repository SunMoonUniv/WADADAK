import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/course_api_client.dart';
import '../../core/auth/auth_controller.dart';

/// 저장한 코스 합계(`GET /courses/bookmarks/summary`). G5 위 칸 · 탭과 E3 `저장한 코스`가 같이 쓴다.
/// 저장 · 해제하면 `ref.invalidate`로 다시 받는다.
final bookmarkSummaryProvider = FutureProvider<BookmarkSummary>((ref) async {
  // 로그인 상태가 정해질 때까지 기다리고, 로그아웃 뒤 다시 로그인했을 때만 다시 받는다
  await ref.watch(authControllerProvider.selectAsync((auth) => auth is SignedIn));
  return ref.read(courseApiClientProvider).bookmarkSummary();
}, retry: (_, _) => null);

/// B1 북마크 버튼(B1-09). 이 코스를 저장했나. 받기 전이나 받지 못하면 저장 안 함으로 보인다.
final courseBookmarkProvider = AsyncNotifierProvider.autoDispose.family<CourseBookmark, bool, String>(
  CourseBookmark.new,
  retry: (_, _) => null,
);

class CourseBookmark extends AsyncNotifier<bool> {
  CourseBookmark(this.courseId);

  final String courseId;

  /// 저장 · 해제를 보내는 중이다.
  var _sending = false;

  @override
  Future<bool> build() async => (await ref.read(courseApiClientProvider).bookmarkedIds([courseId])).contains(courseId);

  /// 누르면 바로 바꿔 보이고 서버에 저장 · 해제한다. 실패하면 되돌리고 오류를 던진다.
  /// 저장 여부를 받는 중이나 보내는 중에는 무시한다. 받기 전에 바꾸면 늦게 온 저장 여부가 덮어쓰고,
  /// 보내는 중에 또 보내면 두 요청의 처리 순서에 따라 화면과 서버가 달라진다.
  Future<void> toggle() async {
    if (state.isLoading || _sending) return;
    final saved = state.value ?? false;
    _sending = true;
    // B1을 닫아도 요청이 끝날 때까지 남아 있어야 저장한 코스 수를 다시 받게 할 수 있다
    final keepAlive = ref.keepAlive();
    state = AsyncData(!saved);
    try {
      final api = ref.read(courseApiClientProvider);
      await (saved ? api.removeBookmarks([courseId]) : api.saveBookmark(courseId));
      ref.invalidate(bookmarkSummaryProvider);
    } catch (_) {
      if (ref.mounted) state = AsyncData(saved);
      rethrow;
    } finally {
      _sending = false;
      keepAlive.close();
    }
  }
}

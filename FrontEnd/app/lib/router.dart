import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/api/course_api_client.dart';
import 'core/auth/auth_controller.dart';
import 'core/map/map_view.dart';
import 'features/course/create/course_info_screen.dart';
import 'features/course/create/route_draw_screen.dart';
import 'features/course/detail/course_detail_screen.dart';
import 'features/course/detail/course_rankings_screen.dart';
import 'features/home/course_filter_screen.dart';
import 'features/home/course_search_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/consent_screen.dart';
import 'features/onboarding/login_screen.dart';
import 'features/onboarding/permission_screen.dart';
import 'features/onboarding/profile_setup_screen.dart';
import 'features/ranking/ranking_screen.dart';
import 'features/ranking/region_ranking_screen.dart';
import 'features/ranking/region_select_screen.dart';
import 'features/review/review_form_screen.dart';
import 'features/review/review_list_screen.dart';
import 'features/run/presentation/free_run_screen.dart';
import 'features/run/presentation/run_history_screen.dart';
import 'features/run/presentation/run_settings_screen.dart';
import 'main_shell.dart';
import 'routes.dart';

/// 로그인 상태가 바뀌면 화면을 다시 고른다.
///
/// - 확인 중 · 로그아웃: A1
/// - 처음 로그인(가입 필요): 소셜 정보 동의부터 온보딩
/// - 로그인: 홈
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier(ref.read(authControllerProvider));
  ref
    ..listen(authControllerProvider, (_, next) => auth.value = next)
    ..onDispose(auth.dispose);

  final router = GoRouter(
    initialLocation: Routes.login,
    refreshListenable: auth,
    redirect: (context, state) {
      final at = state.matchedLocation;
      final onboarding = at.startsWith('/onboarding/');
      return switch (auth.value.value) {
        null || SignedOut() => at == Routes.login ? null : Routes.login,
        SignupRequired() => onboarding ? null : Routes.consent,
        SignedIn() => at == Routes.login || onboarding ? Routes.home : null,
      };
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.consent, builder: (_, _) => const ConsentScreen()),
      GoRoute(path: Routes.permission, builder: (_, _) => const PermissionScreen()),
      GoRoute(path: Routes.profile, builder: (_, _) => const ProfileSetupScreen()),
      GoRoute(path: Routes.courseCreate, builder: (_, state) => RouteDrawScreen(camera: state.extra as MapCamera?)),
      GoRoute(path: Routes.courseInfo, builder: (_, state) => CourseInfoScreen(route: state.extra! as GeneratedRoute)),
      GoRoute(
        path: Routes.courseFilter,
        builder: (_, state) => CourseFilterScreen(request: state.extra! as CourseFilterRequest),
      ),
      // `/course/new` · `/course/filter`보다 뒤에 두어야 그 경로를 코스 ID로 잡지 않는다.
      GoRoute(
        path: '/course/:courseId',
        builder: (_, state) => CourseDetailScreen(courseId: state.pathParameters['courseId']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.home,
              builder: (_, _) => const HomeScreen(),
              routes: [GoRoute(path: 'search', builder: (_, _) => const CourseSearchScreen())],
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.run, builder: (_, _) => const FreeRunScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.ranking, builder: (_, _) => const RankingScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.my, builder: (_, _) => const RunHistoryScreen(myTab: true))]),
        ],
      ),
      GoRoute(path: Routes.runHistory, builder: (_, _) => const RunHistoryScreen()),
      GoRoute(path: Routes.runSettings, builder: (_, _) => const RunSettingsScreen()),
      GoRoute(path: '/my/runs/:id', builder: (_, state) => RunRecordScreen(id: state.pathParameters['id']!)),
      // 하단 탭을 덮는 화면
      GoRoute(path: Routes.rankingRegion, builder: (_, _) => const RegionRankingScreen()),
      GoRoute(path: Routes.rankingRegionSelect, builder: (_, _) => const RegionSelectScreen()),
      GoRoute(
        path: '/course/:courseId/reviews',
        builder: (_, state) =>
            ReviewListScreen(courseId: state.pathParameters['courseId']!, courseName: state.extra as String? ?? ''),
      ),
      GoRoute(
        path: '/course/:courseId/rankings',
        builder: (_, state) {
          final args = state.extra! as CourseRankingsArgs;
          return CourseRankingsScreen(
            courseId: state.pathParameters['courseId']!,
            courseName: args.courseName,
            period: args.period,
          );
        },
      ),
      GoRoute(path: Routes.reviewForm, builder: (_, state) => ReviewFormScreen(args: state.extra! as ReviewFormArgs)),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

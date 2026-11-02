import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/course_api_client.dart';
import '../../core/api/review_api_client.dart';
import '../../core/error_message.dart';
import '../course/course_format.dart';
import '../course/create/course_info_inputs.dart';
import 'my_courses_screen.dart';

/// B7 · 코스 수정(Figma `B7 · 코스 수정`). G4 카드 [수정]에서 연다.
///
/// - 이름 · 난이도 · 특징만 바꾼다(`PUT /courses/{id}`). 경로는 바꿀 수 없어 지도로만 보인다.
/// - 이름 · 난이도 · 특징 칸은 B4 코스 등록과 같다([CourseInfoInputs]). 이름 확인은 이 코스의 지금 이름을 빼고 본다.
/// - 현황: 누적 주행 · 평점(리뷰 API) · 만료까지.
/// - [코스 삭제]는 한 번 묻고 지운다. 지운 뒤에는 G4로 돌아가 카드가 `삭제 예정`으로 바뀐다.
/// - 저장하거나 지우면 바뀐 카드 값을 돌려주며 닫힌다. 바꾼 게 있는데 저장하지 않고 나가면 한 번 묻는다.
/// (2026-11-02 사용자 결정)
class CourseEditScreen extends ConsumerStatefulWidget {
  const CourseEditScreen({super.key, required this.course, this.now});

  final MyCourseItem course;

  /// 만료까지 남은 날을 세는 기준 시각. 테스트만 넣는다.
  final DateTime Function()? now;

  @override
  ConsumerState<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends ConsumerState<CourseEditScreen> with CourseInfoInputs<CourseEditScreen> {
  late final MyCourseItem _course = widget.course;
  ReviewSummary? _reviews;
  bool _saving = false;

  @override
  String get nameCheckCourseId => _course.courseId;

  @override
  void initState() {
    super.initState();
    nameController.text = _course.name;
    difficulty = _course.difficulty;
    tags.addAll(_course.tags);
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final reviews = await ref.read(reviewApiClientProvider).summary(_course.courseId);
      if (mounted) setState(() => _reviews = reviews);
    } catch (_) {
      // 평점은 `—`로 둔다. 수정에는 필요 없다
    }
  }

  bool get _dirty =>
      nameValue != _course.name || difficulty != _course.difficulty || !setEquals(tags, _course.tags.toSet());

  bool get _canSave => _dirty && inputsReady && !_saving;

  Future<void> _save() async {
    stopNameCheck();
    setState(() => _saving = true);
    try {
      final changed = await ref
          .read(courseApiClientProvider)
          .editCourse(_course.courseId, name: nameValue, difficulty: difficulty!, tags: tags);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('코스를 수정했어요.')));
      context.pop(changed);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'COURSE-006') {
        markNameTaken();
      } else {
        showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_saving || !await confirmCourseDelete(context, _course.name) || !mounted) return;
    setState(() => _saving = true);
    try {
      final deleted = await ref.read(courseApiClientProvider).deleteCourse(_course.courseId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('코스를 삭제했어요. 24시간 뒤 완전히 지워져요.')));
      context.pop(deleted);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  /// 앱 바 뒤로 가기 · 휴대폰 뒤로 가기. 바꾼 게 있으면 묻고 나간다. 저장하는 동안은 나가지 않는다.
  Future<void> _leave() async {
    if (_saving) return;
    if (_dirty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('저장하지 않고 나갈까요?'),
          content: const Text('바꾼 내용은 저장되지 않아요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('계속 편집')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('나가기')),
          ],
        ),
      );
      if (leave != true) return;
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final label = WdText.ko16Bold.copyWith(color: WdColors.muted);
    final reviews = _reviews;
    final now = widget.now?.call() ?? DateTime.now();
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: WdColors.paper,
        appBar: WdAppBar(
          title: '코스 수정',
          onBack: _leave,
          action: WdAppBarAction.button('저장', primary: true, onTap: _canSave ? _save : null),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WdSpace.s16,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(WdRadius.r16),
                  child: SizedBox(
                    height: 110,
                    child: Stack(
                      children: [
                        // 경로만 보여 준다. 지도를 움직이지 않게 터치를 막는다
                        IgnorePointer(child: CourseRouteMap(route: _course.route, distanceMarkers: const [])),
                        Positioned(left: WdSpace.s10, top: WdSpace.s10, child: _RouteLockedBadge()),
                      ],
                    ),
                  ),
                ),
                const WdInfoBanner(
                  '기록과 랭킹이 쌓여 있어 경로는 바꿀 수 없어요. 경로를 바꾸려면 새 코스로 등록해 주세요.',
                  tone: WdBannerTone.warning,
                  plain: true,
                ),
                Text('코스 이름', style: label),
                ...nameInputs(),
                Text('난이도', style: label),
                difficultyChips(),
                Text('코스 특징', style: label),
                ...tagChipRows(),
                Text('현황', style: label),
                WdSurface(
                  padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: WdSpace.s4),
                  child: Column(
                    children: [
                      WdListRow(label: '누적 주행', value: '${formatCount(_course.completionCount)}회'),
                      const Divider(height: 1, thickness: 1, color: WdColors.map),
                      WdListRow(
                        label: '평점',
                        value: reviews == null
                            ? '—'
                            : formatCardRating(reviews.averageRating, reviews.reviewCount) ?? '리뷰 없음',
                      ),
                      const Divider(height: 1, thickness: 1, color: WdColors.map),
                      WdListRow(label: '만료까지', value: _expiry(daysUntilExpiry(_course.expiresAt, now))),
                    ],
                  ),
                ),
                const SizedBox(height: WdSpace.s16),
                const WdInfoBanner(
                  '삭제하면 이 코스의 리뷰 · 순위가 함께 사라져요. 내 러닝 기록은 남아요.',
                  tone: WdBannerTone.warning,
                  plain: true,
                ),
                TextButton(
                  onPressed: _saving ? null : _delete,
                  child: Text('코스 삭제', style: WdText.button15.copyWith(color: WdColors.negative)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _expiry(int daysLeft) => daysLeft <= 0 ? 'D-day' : 'D-$daysLeft';
}

/// 지도 왼쪽 위 `경로는 바꿀 수 없어요`(Figma B7).
class _RouteLockedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: WdSpace.s8, vertical: WdSpace.s4),
    decoration: BoxDecoration(color: WdColors.ink, borderRadius: BorderRadius.circular(WdRadius.r12)),
    child: Text('경로는 바꿀 수 없어요', style: WdText.raw(11, FontWeight.w700, 14).copyWith(color: WdColors.white)),
  );
}

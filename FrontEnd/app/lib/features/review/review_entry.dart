import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/review_api_client.dart';
import '../../core/error_message.dart';
import '../../routes.dart';
import 'review_form_screen.dart';

/// 리뷰를 쓸 자격이 없을 때 보이는 안내(정책 공통 5).
const reviewEligibilityGuide = '이 코스를 한 번에 20% 이상(최소 1km) 달리면 리뷰를 쓸 수 있어요.';

/// 다른 화면(마이페이지 내 기록 등)에서 "리뷰 쓰기"를 눌렀을 때 부른다.
///
/// 서버에 이 코스의 내 리뷰 상태(GET /reviews/me)를 물어, 내 리뷰가 있으면 수정(B10),
/// 리뷰를 쓸 수 있는 기록이 있으면 작성(B2), 둘 다 없으면 안내를 띄운다.
/// [courseName]은 B2 · B10 상단에 보인다(리뷰 API에는 없다).
Future<void> openReviewWriter(
  BuildContext context,
  WidgetRef ref, {
  required String courseId,
  required String courseName,
}) async {
  final MyReview my;
  try {
    my = await ref.read(reviewApiClientProvider).mine(courseId);
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;

  if (my.review case final review?) {
    context.push(
      Routes.reviewForm,
      extra: ReviewFormArgs.edit(
        courseId: courseId,
        courseName: courseName,
        review: review,
        record: my.sourceRecord,
        sourceRecordDeleted: my.sourceRecordDeleted,
      ),
    );
  } else if (my.eligibleRecord case final record?) {
    context.push(
      Routes.reviewForm,
      extra: ReviewFormArgs.write(courseId: courseId, courseName: courseName, record: record),
    );
  } else {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(reviewEligibilityGuide)));
  }
}

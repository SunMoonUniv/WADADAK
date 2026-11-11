import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/review_api_client.dart';
import '../../core/error_message.dart';

/// G2-3 안내 문구. 신고가 서버에 저장됐다.
const reviewReportedMessage = '신고가 접수됐어요. 확인 후 처리할게요';

/// G2-4 안내 문구. 이미 신고한 리뷰다(목록의 reportedByMe, 또는 서버의 REVIEW-009).
const reviewAlreadyReportedMessage = '이미 신고한 리뷰예요. 확인 후 처리할게요';

/// 신고 시트를 닫은 결과. 취소 · 바깥 · 뒤로는 null이다.
enum ReviewReportOutcome {
  /// 신고했다(G2-3).
  reported,

  /// 다른 기기에서 먼저 신고해 서버가 거절했다(G2-4).
  alreadyReported,
}

/// 이번 실행에서 신고한 리뷰 ID. 목록을 다시 받기 전에도(코스 상세 B8 미리보기 ↔ G2 전체) 다시 누르면 바로 G2-4를 띄운다.
/// 앱을 다시 켜거나 목록을 새로 받으면 서버의 reportedByMe가 같은 일을 한다.
final reportedReviewIdsProvider = NotifierProvider<ReportedReviewIds, Set<String>>(ReportedReviewIds.new);

class ReportedReviewIds extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String reviewId) => state = {...state, reviewId};
}

/// 다른 러너 리뷰의 ⋯를 눌렀을 때(B8 미리보기 · G2 전체 공통).
/// G2-1 메뉴 → 이미 신고했으면 G2-4, 아니면 G2-2 사유 시트 → G2-3(접수) 또는 G2-4(다른 기기에서 먼저 신고).
Future<void> openReviewMenu(BuildContext context, ReviewCard card) async {
  // 위젯 종류(Consumer 여부)와 상관없이 쓰도록 화면 위의 ProviderScope에서 꺼낸다
  final container = ProviderScope.containerOf(context, listen: false);
  if (!await showReviewMoreSheet(context) || !context.mounted) return;
  if (card.reportedByMe || container.read(reportedReviewIdsProvider).contains(card.reviewId)) {
    showReviewToast(context, reviewAlreadyReportedMessage, done: false);
    return;
  }
  final outcome = await showReviewReportSheet(context, card.reviewId);
  if (outcome == null || !context.mounted) return;
  container.read(reportedReviewIdsProvider.notifier).add(card.reviewId);
  showReviewToast(
    context,
    outcome == ReviewReportOutcome.reported ? reviewReportedMessage : reviewAlreadyReportedMessage,
    done: outcome == ReviewReportOutcome.reported,
  );
}

/// G2-1 · 다른 러너 리뷰의 ⋯ 메뉴. "이 리뷰 신고하기"를 누르면 true다.
Future<bool> showReviewMoreSheet(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: WdColors.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, 0, WdSpace.s24, WdSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WdSpace.s12,
            children: [
              InkWell(
                onTap: () => Navigator.of(context).pop(true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: WdSpace.s14),
                  child: Row(
                    spacing: WdSpace.s12,
                    children: [
                      const Icon(Icons.outlined_flag, color: WdColors.negative, size: 22),
                      Text('이 리뷰 신고하기', style: WdText.ko15Bold.copyWith(color: WdColors.negative)),
                    ],
                  ),
                ),
              ),
              WdButton('취소', variant: WdButtonVariant.secondary, onPressed: () => Navigator.of(context).pop(false)),
            ],
          ),
        ),
      ),
    ) ??
    false;

/// G2-2 · 신고 사유 선택 시트. 신고 API까지 여기서 부르고, 성공하면 결과를 돌려주며 닫힌다.
/// 실패하면 시트를 닫지 않고 아래에 오류를 보여 다시 누를 수 있게 한다.
Future<ReviewReportOutcome?> showReviewReportSheet(BuildContext context, String reviewId) =>
    showModalBottomSheet<ReviewReportOutcome>(
      context: context,
      backgroundColor: WdColors.paper,
      showDragHandle: true,
      // 내용이 길고 키보드가 올라오므로 화면 높이만큼 쓸 수 있게 한다
      isScrollControlled: true,
      builder: (_) => ReviewReportSheet(reviewId: reviewId),
    );

class ReviewReportSheet extends ConsumerStatefulWidget {
  const ReviewReportSheet({super.key, required this.reviewId});

  final String reviewId;

  @override
  ConsumerState<ReviewReportSheet> createState() => _ReviewReportSheetState();
}

class _ReviewReportSheetState extends ConsumerState<ReviewReportSheet> {
  static const _maxDetail = 100; // 서버 detail VARCHAR(100)

  final _detail = TextEditingController();
  ReviewReportReason? _reason;
  var _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detail.addListener(() => setState(() {})); // 글자 수 표시를 바꾼다
  }

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(reviewApiClientProvider).report(widget.reviewId, reason, _detail.text);
      if (mounted) Navigator.of(context).pop(ReviewReportOutcome.reported);
    } on Object catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'REVIEW-009') {
        // 다른 기기에서 먼저 신고했다. 사용자에게는 G2-4와 같은 안내다
        Navigator.of(context).pop(ReviewReportOutcome.alreadyReported);
      } else {
        setState(() => _error = errorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = WdText.label12.copyWith(color: WdColors.muted);
    return Padding(
      // 키보드가 올라오면 그만큼 시트를 올린다
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, 0, WdSpace.s24, WdSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('리뷰 신고', style: WdText.ko20Bold.copyWith(color: WdColors.ink)),
              const SizedBox(height: WdSpace.s6),
              Text('어떤 문제가 있나요? 신고한 사실은 작성자에게 알리지 않아요.', style: WdText.ko13.copyWith(color: WdColors.muted)),
              const SizedBox(height: WdSpace.s16),
              for (final reason in ReviewReportReason.values) ...[
                _ReasonOption(
                  reason: reason,
                  selected: reason == _reason,
                  onTap: _submitting ? null : () => setState(() => _reason = reason),
                ),
                const SizedBox(height: WdSpace.s8),
              ],
              const SizedBox(height: WdSpace.s8),
              Row(
                children: [
                  Expanded(child: Text('자세한 내용 (선택)', style: WdText.ko13Medium.copyWith(color: WdColors.ink))),
                  Text('${_detail.text.length}/$_maxDetail', style: muted),
                ],
              ),
              const SizedBox(height: WdSpace.s6),
              TextField(
                controller: _detail,
                enabled: !_submitting,
                maxLength: _maxDetail,
                maxLines: 3,
                minLines: 3,
                style: WdText.ko13.copyWith(color: WdColors.ink),
                decoration: InputDecoration(
                  hintText: '어떤 점이 문제인지 알려 주세요',
                  hintStyle: WdText.ko13.copyWith(color: WdColors.muted),
                  counterText: '', // 글자 수는 위 줄 오른쪽에 보인다
                  filled: true,
                  fillColor: WdColors.soft,
                  contentPadding: const EdgeInsets.all(WdSpace.s14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WdRadius.r16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: WdSpace.s8),
                Text(_error!, style: WdText.label12.copyWith(color: WdColors.negative)),
              ],
              const SizedBox(height: WdSpace.s16),
              // 사유를 고르기 전에는 누를 수 없다
              WdButton(_submitting ? '신고하는 중…' : '신고하기', onPressed: _reason == null || _submitting ? null : _submit),
            ],
          ),
        ),
      ),
    );
  }
}

/// 사유 한 줄. 고르면 흰 바탕에 검은 테두리, 아니면 연회색 바탕(Figma `Review / Report reason`).
class _ReasonOption extends StatelessWidget {
  const _ReasonOption({required this.reason, required this.selected, required this.onTap});

  final ReviewReportReason reason;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    // 화면 읽기에 "라디오 버튼, 선택됨"으로 읽히게 한다
    inMutuallyExclusiveGroup: true,
    checked: selected,
    child: WdSurface(
      color: selected ? WdColors.paper : WdColors.soft,
      border: BorderSide(color: selected ? WdColors.ink : Colors.transparent, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s16, vertical: WdSpace.s14),
      onTap: onTap,
      child: Row(
        spacing: WdSpace.s12,
        children: [
          // 라디오: 고르면 검은 굵은 링, 아니면 옅은 링
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: WdColors.paper,
              border: Border.all(color: selected ? WdColors.ink : WdColors.checkOff, width: selected ? 6 : 1.5),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(reason.label, style: WdText.ko14Bold.copyWith(color: WdColors.ink)),
                Text(reason.description, style: WdText.label12.copyWith(color: WdColors.muted)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// G2-3 · G2-4 안내창: 검은 바탕 둥근 상자가 아래 떠서 잠깐 보인다. [done]이면 연두 체크, 아니면 안내 아이콘.
void showReviewToast(BuildContext context, String message, {required bool done}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: WdColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(WdRadius.r16)),
        content: Row(
          spacing: WdSpace.s10,
          children: [
            Icon(done ? Icons.check_circle : Icons.info_outline, color: done ? WdColors.lime : WdColors.white, size: 20),
            Expanded(child: Text(message, style: WdText.ko13Medium.copyWith(color: WdColors.white))),
          ],
        ),
      ),
    );
}

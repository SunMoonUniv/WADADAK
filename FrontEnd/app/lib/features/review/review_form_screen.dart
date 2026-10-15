import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/review_api_client.dart';
import '../../core/error_message.dart';
import '../../core/upload/photo_uploader.dart';
import 'review_state.dart';
import 'review_widgets.dart';

/// B2 · B10 화면에 넘기는 값. 작성은 근거 기록이, 수정은 기존 리뷰가 있다.
class ReviewFormArgs {
  /// B2 리뷰 쓰기. [record]는 이 코스에서 리뷰 자격을 얻은 내 기록(작성 요청의 근거 기록).
  const ReviewFormArgs.write({required this.courseId, required this.courseName, required CourseRun this.record})
    : review = null,
      sourceRecordDeleted = false;

  /// B10 리뷰 수정. 근거 기록이 삭제됐으면 [sourceRecordDeleted](B10-1)이고 [record]는 null이다.
  const ReviewFormArgs.edit({
    required this.courseId,
    required this.courseName,
    required ReviewCard this.review,
    required this.record,
    required this.sourceRecordDeleted,
  });

  final String courseId;
  final String courseName;
  final CourseRun? record;
  final ReviewCard? review;
  final bool sourceRecordDeleted;
}

/// B2 · 코스 리뷰 작성 / B10 · 리뷰 수정 / B10-1 · 근거 기록 삭제됨.
///
/// 전체 별점과 항목 평가 4개는 모두 1~5를 골라야 등록된다(정책 공통 5). 후기는 200자, 사진은 5장, 태그는 4개 중 여러 개다.
/// 새 사진은 등록할 때 올리고, 수정하면 사진 목록이 통째로 바뀐다(뺀 사진은 서버가 지운다).
class ReviewFormScreen extends ConsumerStatefulWidget {
  const ReviewFormScreen({super.key, required this.args});

  final ReviewFormArgs args;

  @override
  ConsumerState<ReviewFormScreen> createState() => _ReviewFormScreenState();
}

/// 고른 사진. 이미 올린 사진은 [saved], 새로 고른 사진은 [file]과 미리보기 [bytes]가 있다.
class _FormPhoto {
  _FormPhoto.saved(ReviewPhoto this.saved) : file = null, bytes = null;

  _FormPhoto.picked(XFile this.file, Uint8List this.bytes) : saved = null;

  final ReviewPhoto? saved;
  final XFile? file;
  final Uint8List? bytes;

  ImageProvider get image => saved != null ? NetworkImage(saved!.url) : MemoryImage(bytes!);
}

class _ReviewFormScreenState extends ConsumerState<ReviewFormScreen> {
  static const _maxPhotos = 5;
  static const _maxContent = 200;

  late int _rating;
  late int _safety;
  late int _road;
  late int _lighting;
  late int _amenity;
  late final TextEditingController _content;
  late final Set<ReviewTag> _tags;
  late final List<_FormPhoto> _photos;
  var _saving = false;

  ReviewCard? get _review => widget.args.review;

  bool get _complete => [_rating, _safety, _road, _lighting, _amenity].every((value) => value > 0);

  @override
  void initState() {
    super.initState();
    final review = _review;
    _rating = review?.rating ?? 0;
    _safety = review?.safetyRating ?? 0;
    _road = review?.roadRating ?? 0;
    _lighting = review?.lightingRating ?? 0;
    _amenity = review?.amenityRating ?? 0;
    _content = TextEditingController(text: review?.content ?? '');
    _tags = {...?review?.tags};
    _photos = [for (final photo in review?.photos ?? const <ReviewPhoto>[]) _FormPhoto.saved(photo)];
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final picked = await ref.read(photoUploaderProvider).pick(limit: _maxPhotos - _photos.length);
    final added = [
      for (final file in picked.take(_maxPhotos - _photos.length)) _FormPhoto.picked(file, await file.readAsBytes()),
    ];
    if (mounted && added.isNotEmpty) setState(() => _photos.addAll(added));
  }

  Future<void> _removePhoto(int index) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 사진을 뺄까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('빼기')),
        ],
      ),
    );
    if (remove == true && mounted) setState(() => _photos.removeAt(index));
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final api = ref.read(reviewApiClientProvider);
    final uploader = ref.read(photoUploaderProvider);
    try {
      // 보이는 순서대로 키를 모은다. 새 사진은 이때 한 장씩 올린다
      final keys = [
        for (final photo in _photos) photo.saved?.key ?? await uploader.upload(photo.file!, api.photoUploadForm),
      ];
      final input = ReviewInput(
        rating: _rating,
        safetyRating: _safety,
        roadRating: _road,
        lightingRating: _lighting,
        amenityRating: _amenity,
        content: _content.text,
        tags: _tags,
        photoKeys: keys,
      );
      final review = _review;
      if (review == null) {
        await api.write(widget.args.courseId, widget.args.record!.runRecordId, input);
      } else {
        await api.edit(review.reviewId, input);
      }
      if (!mounted) return;
      refreshCourseReviews(ref, widget.args.courseId);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(review == null ? '리뷰를 등록했어요.' : '리뷰를 수정했어요.')));
      context.pop();
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirmReviewDelete(context) || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(reviewApiClientProvider).delete(_review!.reviewId);
      if (!mounted) return;
      refreshCourseReviews(ref, widget.args.courseId);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('리뷰를 삭제했어요.')));
      context.pop();
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final editing = _review != null;
    final section = WdText.ko16Bold.copyWith(color: WdColors.muted);
    final small = WdText.raw(12, FontWeight.w400, 18);
    return Scaffold(
      appBar: WdAppBar(title: editing ? '리뷰 수정' : '리뷰 쓰기', onBack: () => context.pop()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
        children: [
          // 코스 이름과 근거 기록. B10-1은 근거 기록 대신 삭제 안내
          WdSurface(
            color: WdColors.paper,
            border: const BorderSide(color: WdColors.line),
            padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WdSpace.s4,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(args.courseName, style: WdText.ko14Bold.copyWith(color: WdColors.ink)),
                ),
                if (args.sourceRecordDeleted)
                  Text('근거 기록이 삭제됐어요 · 리뷰 수정은 가능해요', style: small.copyWith(color: WdColors.warningText))
                else if (args.record case final record?)
                  Text(courseRunLine(record), style: small.copyWith(color: WdColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: WdSpace.s16),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WdSpace.s6),
            child: Column(
              spacing: WdSpace.s6,
              children: [
                Text(editing ? '평점' : '이 코스 어땠나요?', style: small.copyWith(color: WdColors.muted)),
                _BigStars(value: _rating, onChanged: (value) => setState(() => _rating = value)),
              ],
            ),
          ),
          const SizedBox(height: WdSpace.s16),
          Text('항목별 평가', style: section),
          const SizedBox(height: WdSpace.s16),
          WdRatingRow(label: '안전성 (차량 · 인적)', value: _safety, onChanged: (value) => setState(() => _safety = value)),
          WdRatingRow(label: '도로 상태', value: _road, onChanged: (value) => setState(() => _road = value)),
          WdRatingRow(label: '야간 조명', value: _lighting, onChanged: (value) => setState(() => _lighting = value)),
          WdRatingRow(label: '편의시설 (화장실/편의점)', value: _amenity, onChanged: (value) => setState(() => _amenity = value)),
          const SizedBox(height: WdSpace.s16),
          Text('한줄 후기', style: section),
          const SizedBox(height: WdSpace.s16),
          SizedBox(
            height: 88,
            child: TextField(
              controller: _content,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              inputFormatters: [LengthLimitingTextInputFormatter(_maxContent)],
              style: small.copyWith(color: WdColors.ink),
              cursorColor: WdColors.ink,
              decoration: InputDecoration(
                hintText: '코스에 대한 솔직한 후기를 남겨주세요',
                hintStyle: small.copyWith(color: WdColors.muted),
                filled: true,
                fillColor: WdColors.soft,
                contentPadding: const EdgeInsets.all(WdSpace.s12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(WdRadius.r16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: WdSpace.s16),
          Text('사진 첨부', style: section),
          const SizedBox(height: WdSpace.s16),
          WdPhotoUpload(
            photos: [for (final photo in _photos) photo.image],
            onAdd: _photos.length < _maxPhotos ? _addPhotos : null,
            onTapPhoto: _removePhoto,
          ),
          const SizedBox(height: WdSpace.s16),
          Wrap(
            spacing: WdSpace.s6,
            runSpacing: WdSpace.s6,
            children: [
              for (final tag in ReviewTag.values)
                WdFilterChip(
                  tag.label,
                  height: 36,
                  selected: _tags.contains(tag),
                  onTap: () => setState(() => _tags.contains(tag) ? _tags.remove(tag) : _tags.add(tag)),
                ),
            ],
          ),
          if (editing) ...[
            const SizedBox(height: 45),
            Center(
              child: TextButton(
                onPressed: _saving ? null : _delete,
                child: Text('이 리뷰 삭제', style: WdText.raw(12, FontWeight.w500, 18).copyWith(color: WdColors.negative)),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: WdBottomBar.pinned(
        primary: WdButton(editing ? '수정 완료' : '리뷰 등록', onPressed: _complete && !_saving ? _submit : null),
      ),
    );
  }
}

/// 전체 별점(28px, ink). 누른 별까지 채운다.
class _BigStars extends StatelessWidget {
  const _BigStars({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 5; i++)
        Semantics(
          button: true,
          selected: i < value,
          label: '전체 별점 ${i + 1}점',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(i + 1),
            child: Text(
              '${i < value ? '★' : '☆'}${i < 4 ? ' ' : ''}',
              style: WdText.raw(28, FontWeight.w400, 39).copyWith(color: WdColors.ink),
            ),
          ),
        ),
    ],
  );
}

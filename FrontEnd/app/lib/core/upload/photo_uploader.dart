import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/upload_form.dart';

/// 사진 업로드(개발 정책 7장): 고르기 → JPEG 변환(긴 변 2048px · 품질 85 · EXIF 제거) → 업로드 폼 → 저장소에 직접 POST → 키.
/// 키를 가입 · 리뷰 저장 요청에 담는다.
class PhotoUploader {
  PhotoUploader({
    Dio? storage,
    ImagePicker? picker,
    Future<Uint8List> Function(String path)? toJpeg,
  })  : _storage = storage ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), sendTimeout: const Duration(seconds: 60))),
        _picker = picker ?? ImagePicker(),
        _toJpeg = toJpeg ?? _compress;

  static const maxSide = 2048.0;

  final Dio _storage;
  final ImagePicker _picker;
  final Future<Uint8List> Function(String path) _toJpeg;

  /// 갤러리에서 [limit]장까지 고른다. 긴 변은 이때 2048px 이하로 줄인다. 고르지 않으면 빈 목록.
  /// 메타데이터를 읽지 않으므로 iOS 14 이상은 사진 보관함 권한을 묻지 않는다.
  Future<List<XFile>> pick({int limit = 1}) async => limit == 1
      ? [?await _picker.pickImage(source: ImageSource.gallery, maxWidth: maxSide, maxHeight: maxSide, requestFullMetadata: false)]
      : await _picker.pickMultiImage(maxWidth: maxSide, maxHeight: maxSide, limit: limit, requestFullMetadata: false);

  /// 사진 한 장을 올리고 키를 돌려준다. [requestForm]은 키를 저장할 모듈의 업로드 폼 API다.
  Future<String> upload(XFile photo, Future<UploadForm> Function() requestForm) async {
    final jpeg = await _toJpeg(photo.path);
    final form = await requestForm();
    try {
      await _storage.post<void>(
        form.url,
        data: FormData.fromMap({
          ...form.fields,
          'file': MultipartFile.fromBytes(jpeg, filename: 'photo.jpg', contentType: DioMediaType('image', 'jpeg')),
        }),
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
    return form.key;
  }

  /// 촬영 위치 등 EXIF를 지우고 방향은 픽셀에 반영한다. 크기는 [pick]에서 줄였으므로 더 줄이지 않는다.
  static Future<Uint8List> _compress(String path) async {
    final jpeg = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: maxSide.toInt(),
      minHeight: maxSide.toInt(),
      quality: 85,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (jpeg == null) throw const ApiException('PHOTO_FORMAT', '이 사진은 올릴 수 없어요. 다른 사진을 골라 주세요.');
    return jpeg;
  }
}

final photoUploaderProvider = Provider<PhotoUploader>((ref) => PhotoUploader());

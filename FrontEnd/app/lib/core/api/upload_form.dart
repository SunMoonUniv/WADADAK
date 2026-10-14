/// 서버가 준 사진 업로드 폼(S3 Presigned POST). [fields]를 모두 넣고 파일을 마지막에 붙여 [url]에 POST한다.
/// 폼을 주는 API는 키를 저장하는 모듈마다 있다(가입 프로필 사진, 리뷰 사진).
class UploadForm {
  UploadForm.fromJson(Map<dynamic, dynamic> json)
      : url = json['url'] as String,
        key = json['key'] as String,
        fields = Map<String, String>.from(json['fields'] as Map);

  final String url;
  final String key;
  final Map<String, String> fields;
}

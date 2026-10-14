import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/upload/photo_uploader.dart';

/// 받은 요청을 남기고 [respond]로 답한다.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.respond);

  final ResponseBody Function(RequestOptions request) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final form = {
    'url': 'https://files.test/wadadak',
    'key': 'review/0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b.jpg',
    'fields': {'key': 'review/0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b.jpg', 'Content-Type': 'image/jpeg', 'policy': 'p'},
  };
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  late _Recorder api;

  setUp(() {
    api = _Recorder((_) => ResponseBody.fromString(jsonEncode({'result': 'SUCCESS', 'data': form}), 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        }));
  });

  PhotoUploader uploader(_Recorder storage, {List<String>? converted}) => PhotoUploader(
        api: Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = api,
        storage: Dio()..httpClientAdapter = storage,
        toJpeg: (path) async {
          converted?.add(path);
          return jpeg;
        },
      );

  test('converts, gets a review upload form and posts the fields with the file last', () async {
    final storage = _Recorder((_) => ResponseBody.fromString('', 204));
    final converted = <String>[];

    final key = await uploader(storage, converted: converted).upload(XFile('/photos/run.heic'), PhotoUse.review);

    expect(key, form['key']);
    expect(converted, ['/photos/run.heic']);
    expect(api.requests.single.method, 'POST');
    expect(api.requests.single.path, '/api/v1/reviews/photo-uploads');
    final upload = storage.requests.single;
    expect(upload.uri.toString(), 'https://files.test/wadadak');
    final data = upload.data as FormData;
    expect({for (final field in data.fields) field.key: field.value}, form['fields']);
    expect(data.files.single.key, 'file');
    expect(data.files.single.value.contentType.toString(), 'image/jpeg');
    expect(data.files.single.value.length, jpeg.length);
  });

  test('a rejected upload becomes an ApiException with the status', () async {
    final storage = _Recorder((_) => ResponseBody.fromString('<Error><Code>AccessDenied</Code></Error>', 403));

    await expectLater(
      uploader(storage).upload(XFile('/photos/run.jpg'), PhotoUse.review),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
  });
}

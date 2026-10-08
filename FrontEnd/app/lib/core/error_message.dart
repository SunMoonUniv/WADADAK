import 'package:flutter/material.dart';

import 'api/api_client.dart';

/// 오류를 화면 아래 스낵바로 알린다. 서버 오류는 서버가 준 문구를 쓴다.
void showError(BuildContext context, Object error) {
  final message = error is ApiException && error.message.isNotEmpty ? error.message : '문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

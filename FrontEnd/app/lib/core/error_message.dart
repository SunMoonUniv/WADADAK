import 'package:flutter/material.dart';

import 'api/api_client.dart';

/// 화면에 보일 오류 문구. 서버 오류는 서버가 준 문구를 쓴다.
String errorMessage(Object error) =>
    error is ApiException && error.message.isNotEmpty ? error.message : '문제가 생겼어요. 잠시 후 다시 시도해 주세요.';

/// 오류를 화면 아래 스낵바로 알린다. [onRetry]가 있으면 `다시 시도`를 붙인다.
void showError(BuildContext context, Object error, {VoidCallback? onRetry}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(errorMessage(error)),
      action: onRetry == null ? null : SnackBarAction(label: '다시 시도', onPressed: onRetry),
    ));
}

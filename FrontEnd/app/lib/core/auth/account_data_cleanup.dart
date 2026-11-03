import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app composition root supplies feature-owned local cleanup.
final accountDataCleanupProvider = Provider<Future<void> Function(String)>((
  ref,
) {
  throw StateError('회원 탈퇴의 기기 자료 정리가 연결되지 않았어요.');
});

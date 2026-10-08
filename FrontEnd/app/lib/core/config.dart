/// 앱은 서버 주소 하나만 안다(개발 정책 9장).
///
/// 기본값은 Android 에뮬레이터에서 본 개발 PC의 localhost다.
/// 다른 주소로 실행: `flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8080`
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');

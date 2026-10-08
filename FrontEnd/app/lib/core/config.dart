/// 앱은 서버 주소 하나만 안다(개발 정책 9장).
///
/// 기본값은 Android 에뮬레이터에서 본 개발 PC의 localhost다.
/// 다른 주소로 실행: `flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8080`
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');

/// 소셜 로그인 방식. 서버의 `app.member.social.fake`와 반대로 맞춘다.
/// - false(기본): 가짜 로그인. 로컬 서버 기본값(fake: true)과 짝이다
/// - true: 카카오 SDK 로그인. 서버를 `app.member.social.fake=false`와 `KAKAO_APP_ID`로 띄운다
///
/// 실제 로그인으로 실행: `flutter run --dart-define=REAL_SOCIAL_LOGIN=true`
const realSocialLogin = bool.fromEnvironment('REAL_SOCIAL_LOGIN');

/// 카카오 네이티브 앱 키. 앱 안에 들어가는 공개 값이다. 어드민 키는 앱·저장소 어디에도 두지 않는다.
/// AndroidManifest.xml·Info.plist의 URL 스킴 `kakao{키}`와 같아야 한다.
const kakaoNativeAppKey = '57b43e47368fd814ab5a8ae64dd726d3';

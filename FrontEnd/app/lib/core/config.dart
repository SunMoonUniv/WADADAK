/// 앱은 서버 주소 하나만 안다(개발 정책 9장).
///
/// 기본값은 Android 에뮬레이터에서 본 개발 PC의 localhost다.
/// 다른 주소로 실행: `flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8080`
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');

/// 소셜 로그인 방식. 서버의 `app.member.social.fake`와 반대로 맞춘다.
/// - true(기본): 카카오 SDK 로그인. 서버 기본값(fake: false)과 짝이다
/// - false: 가짜 로그인. 서버를 `app.member.social.fake=true`로 띄운다
///
/// 가짜 로그인으로 실행: `flutter run --dart-define=REAL_SOCIAL_LOGIN=false`
const realSocialLogin = bool.fromEnvironment('REAL_SOCIAL_LOGIN', defaultValue: true);

/// 카카오 네이티브 앱 키. 앱 안에 들어가는 공개 값이다. 어드민 키는 앱·저장소 어디에도 두지 않는다.
/// AndroidManifest.xml·Info.plist의 URL 스킴 `kakao{키}`와 같아야 한다.
const kakaoNativeAppKey = '57b43e47368fd814ab5a8ae64dd726d3';

/// 지도 방식.
/// - true(기본): 네이버 지도 SDK
/// - false: 키 없이 도는 개발용 지도(배경색 위에 선·표지만 그린다)
///
/// 개발용 지도로 실행: `flutter run --dart-define=REAL_MAP=false`
const realMap = bool.fromEnvironment('REAL_MAP', defaultValue: true);

/// 네이버 지도(NCP Maps · Dynamic Map) Client ID. 앱 안에 들어가는 공개 값이다. Client Secret은 쓰지 않으며 앱·저장소 어디에도 두지 않는다.
/// NCP 콘솔 Application에 앱 ID `com.wadadak.app`(Android 패키지 이름 · iOS Bundle ID)으로 등록했다.
const naverMapClientId = '4jno8yckyz';

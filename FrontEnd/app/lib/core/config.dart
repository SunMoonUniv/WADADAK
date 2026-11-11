/// 앱은 서버 주소 하나만 안다(개발 정책 9장).
///
/// 기본값은 Android 에뮬레이터에서 본 개발 PC의 localhost다.
/// 다른 주소로 실행: `flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8080`
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');

/// 소셜 로그인 방식. 서버의 `app.member.social.fake`와 반대로 맞춘다.
/// - true(기본): 카카오·Google SDK 로그인. 서버 기본값(fake: false)과 짝이다
/// - false: 가짜 로그인. 서버를 `app.member.social.fake=true`로 띄운다
///
/// 가짜 로그인으로 실행: `flutter run --dart-define=REAL_SOCIAL_LOGIN=false`
const realSocialLogin = bool.fromEnvironment('REAL_SOCIAL_LOGIN', defaultValue: true);

/// 카카오 네이티브 앱 키. 앱 안에 들어가는 공개 값이다. 어드민 키는 앱·저장소 어디에도 두지 않는다.
/// AndroidManifest.xml·Info.plist의 URL 스킴 `kakao{키}`와 같아야 한다.
const kakaoNativeAppKey = '57b43e47368fd814ab5a8ae64dd726d3';

/// Google 웹 클라이언트 ID(Google Cloud `wadadak-server`). 앱 안에 들어가는 공개 값이다.
/// Android·iOS 모두 이 값을 serverClientId로 넘겨야 ID 토큰의 aud가 이 값이 되고, 서버가 검증할 수 있다.
/// 서버의 `GOOGLE_CLIENT_IDS`(app.member.social.google-client-ids)와 같아야 한다.
const googleServerClientId = '1048451496052-jmrq4n20oah17vkcru3qv6gikrc23obs.apps.googleusercontent.com';

/// Google iOS 클라이언트 ID(Google Cloud `wadadak-ios`, 번들 ID com.wadadak.app). iOS에서만 쓴다.
/// Info.plist의 URL 스킴(역방향 클라이언트 ID `com.googleusercontent.apps.…`)과 짝이다.
const googleIosClientId = '1048451496052-d45s2heki1u509122fh6g7d3q5cpdpre.apps.googleusercontent.com';

/// 지도 방식.
/// - true(기본): 네이버 지도 SDK
/// - false: 키 없이 도는 개발용 지도(배경색 위에 선·표지만 그린다)
///
/// 개발용 지도로 실행: `flutter run --dart-define=REAL_MAP=false`
const realMap = bool.fromEnvironment('REAL_MAP', defaultValue: true);

/// 코스 만들기의 `자동 생성` 탭(B3 고도화). 서버 코스 자동 생성 API가 공용 서버에 배포된 것을 확인한 뒤 기본값을 true로 바꾼다.
/// 끄면 탭을 그리지 않는다. 서버에는 끄는 설정이 없다(코스 자동 생성 구현 계획 6절).
///
/// 켜서 실행: `flutter run --dart-define=AUTO_COURSE=true`
const autoCourse = bool.fromEnvironment('AUTO_COURSE', defaultValue: false);

/// 네이버 지도(NCP Maps · Dynamic Map) Client ID. 앱 안에 들어가는 공개 값이다. Client Secret은 쓰지 않으며 앱·저장소 어디에도 두지 않는다.
/// NCP 콘솔 Application에 앱 ID `com.wadadak.app`(Android 패키지 이름 · iOS Bundle ID)으로 등록했다.
const naverMapClientId = '4jno8yckyz';

/// 푸시 알림(F14)용 Firebase 앱 값(Firebase 프로젝트 `wadadak-511404`, Android 앱 `com.wadadak.app`).
/// `google-services.json`에 든 값과 같다. 앱 안에 들어가는 공개 값이라 지도 Client ID처럼 그대로 둔다.
/// 비밀은 서버의 서비스 계정 키뿐이다(deploy README 6번). 이 값만으로는 푸시를 보낼 수 없다.
///
/// - 파일 대신 여기 두어 Google 서비스 Gradle 플러그인 없이 연결한다(`FirebaseOptions`, push_service.dart).
/// - API 키는 구글 클라우드 콘솔에서 Firebase API만 쓰도록 제한해 두었다(애플리케이션 제한은 없음: 팀원마다 디버그 서명이 달라서).
/// - 지금은 Android만 연결한다. iOS는 APNs 키 등록과 함께 Apple 출시 때 붙인다.
const firebaseApiKey = 'AIzaSyCh_YMiN-7dwLq4f4_hx8yooTz9R_tujNM';
const firebaseAppId = '1:245489471522:android:f561560b7b827f4bd33a7b';
const firebaseSenderId = '245489471522'; // 프로젝트 번호
const firebaseProjectId = 'wadadak-511404';

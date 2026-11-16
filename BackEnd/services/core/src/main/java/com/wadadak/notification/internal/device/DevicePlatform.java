package com.wadadak.notification.internal.device;

/** 기기 종류. FCM은 둘 다 같은 토큰으로 보낸다(iOS는 FCM이 APNs로 넘긴다). 지금 앱은 Android만 낸다 */
enum DevicePlatform {
    ANDROID,
    IOS
}

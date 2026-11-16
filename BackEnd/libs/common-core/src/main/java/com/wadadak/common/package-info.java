/**
 * 도메인에 종속되지 않는 공통 인프라. 하위 패키지까지 공개한다(개발 정책 3.1·3.3).
 * 다른 모듈을 import하지 않는다.
 */
@ApplicationModule(type = ApplicationModule.Type.OPEN)
package com.wadadak.common;

import org.springframework.modulith.ApplicationModule;

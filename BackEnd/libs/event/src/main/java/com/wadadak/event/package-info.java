/**
 * 모듈 간 이벤트 record(메시지 계약). 하위 패키지는 발행 모듈 이름이다(개발 정책 5.3).
 * 필드는 추가만 한다. 다른 모듈을 import하지 않는다.
 */
@ApplicationModule(type = ApplicationModule.Type.OPEN)
package com.wadadak.event;

import org.springframework.modulith.ApplicationModule;

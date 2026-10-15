package com.wadadak.run.internal.judging;

import com.wadadak.common.geo.GeoPoint;

import java.time.Instant;

/**
 * 세션 기록의 입력 한 건. 필드 이름은 앱 입력 JSON과 같다(run/1번-F5-구현-1단계 공통 계약).
 *
 * @param seq        세션 안의 단일 순번
 * @param elapsedMs  START 기준 경과 ms(START = 0)
 * @param measuredAt 측정 시각(UTC)
 * @param location   GPS 입력에만 있다. 나머지는 null
 * @param accuracyM  GPS 정확도(m). GPS 입력에만 있다. 나머지는 null
 */
record RunInput(long seq, Kind kind, long elapsedMs, Instant measuredAt, GeoPoint location, Double accuracyM) {

    enum Kind {START, GPS, PAUSE, RESUME, GAP, SEGMENT_END, END}
}

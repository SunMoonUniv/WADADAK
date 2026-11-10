package com.wadadak.course.internal.planner;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.Set;

/**
 * 코스 자동 생성 조건(A7 폼, 정책 B3-A01). 문장으로 채운 결과(parse 응답)와 생성 요청에 같이 쓴다.
 * 칸끼리 맞는지(편도의 도착지 등)는 {@link PlanRequest}가 본다.
 *
 * @param start       출발. 문장에서 못 읽으면 현재 위치
 * @param shape       모양. 문장에서 못 읽으면 한 바퀴
 * @param endQuery    편도의 도착지 이름
 * @param viaQuery    경유의 경유지 이름(1곳)
 * @param distanceM   목표 거리(m). 있으면 시간보다 먼저 쓴다
 * @param durationMin 목표 시간(분). 평소 페이스로 거리로 바꾼다
 * @param prefer      원하는 길. null이면 없음
 * @param message     parse 응답에서만: 코스와 무관한 문장이면 안내 문구, 이때 나머지 칸은 비어 있다. 생성 요청에서는 무시한다
 */
record PlanForm(@NotNull @Valid Start start,
                @NotNull Shape shape,
                @Size(max = 100) String endQuery,
                @Size(max = 100) String viaQuery,
                @Min(1_000) @Max(100_000) Integer distanceM,
                @Min(5) @Max(600) Integer durationMin,
                Set<Pref> prefer,
                String message) {

    /** @param query 장소 이름. kind가 CURRENT면 null */
    record Start(@NotNull StartKind kind, @Size(max = 100) String query) {
    }

    enum StartKind {CURRENT, PLACE}

    enum Shape {
        /** 한 바퀴. 1~22km(정책 B3-A02) */
        LOOP,
        /** 왕복 */
        OUT_AND_BACK,
        /** 편도. endQuery 필수 */
        POINT_TO_POINT,
        /** 경유지 1곳을 거쳐 출발지로. viaQuery 필수 */
        VIA
    }

    /** 원하는 길. 지금 후보에 반영하는 것은 {@link #SUPPORTED}뿐이고, 나머지는 후보의 notApplied로 알린다(정책 B3-A03) */
    enum Pref {
        FLAT, HILLY, SIDEWALK, AVOID_ARTERIAL, STORE_ON_ROUTE, TOILET_ON_ROUTE, RIVER, PARK, NO_RETRACE;

        static final Set<Pref> SUPPORTED = Set.of(AVOID_ARTERIAL, STORE_ON_ROUTE, NO_RETRACE);
    }
}

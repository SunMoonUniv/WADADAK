package com.wadadak.ranking;

/**
 * 랭킹 기간(정책 공통 6, B9-01·G3-01). 기록 등록 시각을 Asia/Seoul 기준으로 나눈다.
 * 오프라인으로 늦게 올라온 기록도 등록된 기간에 들어간다. B1·B8 고스트 자동 선택의 기본값은 {@link #ALL}이다.
 */
public enum RankingPeriod {
    /** 전체 기간 */
    ALL,
    /** 이번 달 1일 00:00부터 */
    MONTH,
    /** 이번 주 월요일 00:00부터 */
    WEEK
}

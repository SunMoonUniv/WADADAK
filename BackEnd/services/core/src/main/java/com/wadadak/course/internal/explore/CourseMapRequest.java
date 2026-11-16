package com.wadadak.course.internal.explore;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.course.Difficulty;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import org.springframework.format.annotation.DateTimeFormat;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Set;

/**
 * 지도 범위(남서쪽·북동쪽 끝)와 필터. 필터 값이 없으면 그 조건은 걸지 않는다.
 *
 * @param minDistanceMeters FIL-02 거리 하한(포함)
 * @param maxDistanceMeters FIL-02 거리 상한(포함). {@code 20km+}를 고르면 보내지 않는다
 * @param difficulties      FIL-03. 그중 하나면 된다. 없으면 전체
 * @param minRating         FIL-03 최소 평점(포함). 전체 기간 평점(소수 첫째 자리 반올림)으로 본다. 리뷰가 없는 코스는 빠진다
 * @param tags              FIL-04. 모두 가진 코스만(AND)
 * @param courseType        FIL-05. 없으면 전체
 * @param query             G6에서 고른 검색어(SEA-04 · SEA-07). 이름에 이 말이 들어간 코스만. 검색(G1 · G6)과 같이 공백 · 대소문자는 보지 않는다
 * @param regionCode        G6에서 고른 지역. 출발점이 이 시·군·구(법정동 코드 10자리)인 코스만
 * @param startDate         FIL-09 인기순 기간 시작일(포함, Asia/Seoul). 없으면 처음부터
 * @param endDate           FIL-09 인기순 기간 종료일(포함). 없으면 끝없이. 기간을 주면 그 기간에 도전 · 조회 · 리뷰가 없는 코스는 빠진다. 그 기간에 등록한 코스는 남는다
 */
record CourseMapRequest(
        @NotNull Double swLat,
        @NotNull Double swLng,
        @NotNull Double neLat,
        @NotNull Double neLng,
        @PositiveOrZero Integer minDistanceMeters,
        @PositiveOrZero Integer maxDistanceMeters,
        Set<Difficulty> difficulties,
        @DecimalMin("0.0") @DecimalMax("5.0") BigDecimal minRating,
        Set<CourseTag> tags,
        CourseType courseType,
        @Size(max = CourseSearchRequest.MAX_LENGTH) String query,
        @Pattern(regexp = "\\d{10}") String regionCode,
        @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
        @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate) {

    /**
     * 좌표 범위를 벗어났거나, 남서쪽 끝이 북동쪽 끝보다 크거나, 거리 하한이 상한보다 크거나,
     * 검색어가 공백을 빼고 2글자 미만이거나, 기간 시작일이 종료일보다 늦으면 COMMON-001.
     */
    CourseMapRequest requireValid() {
        GeoPoint southWest = new GeoPoint(swLat, swLng);
        GeoPoint northEast = new GeoPoint(neLat, neLng);
        if (southWest.lat() > northEast.lat() || southWest.lng() > northEast.lng()) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "지도 범위의 남서쪽 끝이 북동쪽 끝보다 큽니다.");
        }
        if (minDistanceMeters != null && maxDistanceMeters != null && minDistanceMeters > maxDistanceMeters) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "거리 하한이 상한보다 큽니다.");
        }
        if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "기간 시작일(startDate)이 종료일(endDate)보다 늦습니다.");
        }
        nameKey();
        return this;
    }

    /**
     * 목록을 [sort]로 줄 수 있나. 기간은 인기순에만 보낸다.
     *
     * @throws AppException COMMON-001 — 인기순이 아닌데 기간을 보냈을 때
     */
    CourseMapRequest requirePeriodFor(CourseListSort sort) {
        if (period() != null && sort != CourseListSort.POPULAR) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "기간(startDate · endDate)은 인기순(POPULAR)에만 보냅니다.");
        }
        return this;
    }

    /** 인기순 기간(FIL-09). 두 날짜를 모두 보내지 않았으면 null(전체 기간)이다. */
    CourseListPeriod period() {
        return startDate == null && endDate == null ? null : new CourseListPeriod(startDate, endDate);
    }

    /** [query]를 이름 키로 바꾼 것. 검색어 조건이 없으면 null. */
    String nameKey() {
        return query == null ? null : CourseSearchRequest.keyOf(query);
    }
}

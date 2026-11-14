package com.wadadak.course.internal.planner;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.paging.NumberedPage;
import com.wadadak.common.response.ApiResult;
import com.wadadak.course.internal.planner.AdminPlannerLogQueries.Detail;
import com.wadadak.course.internal.planner.AdminPlannerLogQueries.Result;
import com.wadadak.course.internal.planner.AdminPlannerLogQueries.Row;
import com.wadadak.course.internal.planner.AdminPlannerLogQueries.Stats;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/**
 * 운영자 웹 "코스 생성 로그"(분석 로그, 개발 정책 코스 자동 생성 규칙). 운영자 계정(HTTP Basic)으로만 부른다(SecurityConfig).
 *
 * <p>URL은 다른 운영자 API처럼 {@code /api/v1/admin/…} 아래에 둔다. 나중에 course를 떼어내면 게이트웨이가
 * {@code /api/v1/admin/planner-logs}를 course로 보낸다. days는 최근 며칠(오늘 포함, Asia/Seoul, 1~365), 없으면 전체 기간.
 */
@RestController
@RequestMapping("/api/v1/admin/planner-logs")
@RequiredArgsConstructor
class AdminPlannerLogController {

    private final AdminPlannerLogQueries queries;
    private final Clock clock;

    @Operation(summary = "[운영자] 코스 생성 로그 숫자 카드",
            description = "기간 안의 문장 채우기 수 · 코스 찾기 수 · Jev 사용률 · 폼 수정률 · 후보 없음 비율(0~1) · 코스 찾기 평균 시간(ms). "
                    + "셀 것이 없으면 비율은 null.")
    @GetMapping("/stats")
    ApiResult<Stats> stats(@RequestParam(required = false) @Min(1) @Max(365) Integer days) {
        return ApiResult.success(queries.stats(since(days)));
    }

    @Operation(summary = "[운영자] 코스 생성 로그 목록",
            description = "문장 하나에 한 줄, 최신순. plan은 그 문장에 이어진 마지막 코스 찾기(안 했으면 null)와 횟수. "
                    + "result: FOUND 후보 있음 · NONE 후보 없음 · NOT_PLANNED 찾기 안 함. jev: true Jev 사용 · false 규칙만. "
                    + "user는 회원 해시 앞 8자리(같은 사람끼리 같다).")
    @GetMapping
    ApiResult<NumberedPage<Row>> rows(
            @RequestParam(required = false) @Min(1) @Max(365) Integer days,
            @RequestParam(required = false) Result result,
            @RequestParam(required = false) Boolean jev,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size) {
        return ApiResult.success(queries.rows(since(days), result, jev, page * size, size));
    }

    @Operation(summary = "[운영자] 코스 생성 로그 상세",
            description = "문장 · Jev 답(질문별 확률) · 채운 폼과, 이어진 코스 찾기 전부(보낸 폼 · 수정 여부 · 후보 전부 · 단계별 시간). "
                    + "없으면 COMMON-004.")
    @GetMapping("/{id}")
    ApiResult<Detail> detail(@PathVariable UUID id) {
        Detail detail = queries.detail(id);
        if (detail == null) {
            throw new AppException(CommonErrorCode.NOT_FOUND);
        }
        return ApiResult.success(detail);
    }

    @Operation(summary = "[운영자] 코스 생성 로그 CSV",
            description = "논문 분석용. 채우기와 코스 찾기를 이어 한 줄씩(찾기 안 한 문장 · 직접 조건으로 찾은 요청 포함). "
                    + "UTF-8(BOM), 시각은 한국 시각, 후보는 경로 점을 뺀 지표만.")
    @GetMapping("/export")
    ResponseEntity<byte[]> export(@RequestParam(required = false) @Min(1) @Max(365) Integer days) {
        return ResponseEntity.ok()
                .contentType(new MediaType("text", "csv", StandardCharsets.UTF_8))
                // 받은 파일 이름: planner-logs-2026-11-24.csv
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment()
                        .filename("planner-logs-%s.csv".formatted(LocalDate.now(clock.withZone(TimeConfig.SEOUL)))).build().toString())
                .body(queries.csv(since(days)).getBytes(StandardCharsets.UTF_8));
    }

    /** 최근 며칠(오늘 포함)의 시작 시각. null이면 전체 기간 */
    private Instant since(Integer days) {
        return days == null ? null
                : LocalDate.now(clock.withZone(TimeConfig.SEOUL)).minusDays(days - 1L).atStartOfDay(TimeConfig.SEOUL).toInstant();
    }
}

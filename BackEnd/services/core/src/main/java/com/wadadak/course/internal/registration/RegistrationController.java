package com.wadadak.course.internal.registration;

import com.wadadak.common.response.ApiResult;
import com.wadadak.course.internal.route.GeneratedRoute;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/courses")
@RequiredArgsConstructor
class RegistrationController {

    private final RegistrationService registrationService;

    @Operation(summary = "사용자 지정 코스 등록 (B4-07)",
            description = "입력점으로 경로를 다시 만들어 검증하고 바로 공개한다. 같은 Idempotency-Key로 재요청하면 처음 결과를 돌려준다. "
                    + "이름 길이 COMMON-001, 입력점·거리 COURSE-003~005, 이름 중복 006, 85% 유사 007, 일일 한도 008(429), 출발점 지역 없음 009.")
    @PostMapping
    ApiResult<RegisteredCourse> register(
            @AuthenticationPrincipal Jwt jwt,
            @Parameter(description = "등록 시도마다 앱이 만드는 UUID. 같은 등록을 재시도할 때는 같은 값") @RequestHeader("Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody RegisterCourseRequest request) {
        return ApiResult.success(registrationService.registerCustom(UUID.fromString(jwt.getSubject()), idempotencyKey, request));
    }

    @Operation(summary = "GPS 코스 경로 미리보기 (D4)",
            description = "러닝 기록 경로 조각(course-source segments)을 이어 점을 줄인 경로·거리·1km 표지를 돌려준다. 저장하지 않는다. "
                    + "이미 등록한 기록 COURSE-010, 점 2개 미만 003, 1km 미만 004, 조각 사이 빈칸을 이을 수 없음 011(GPS 정확도 부족). "
                    + "거리 상한은 없다. 이름·유사도·출발점 지역·일일 한도는 등록 때 본다.")
    @PostMapping("/gps/route")
    ApiResult<GeneratedRoute> previewGps(@Valid @RequestBody GpsRouteRequest request) {
        return ApiResult.success(registrationService.previewGps(request));
    }

    @Operation(summary = "GPS 코스 등록 (D4)",
            description = "미리보기와 같은 경로를 다시 만들어 검증하고 바로 공개한다. 같은 Idempotency-Key로 재요청하면 처음 결과를 돌려준다. "
                    + "이름 길이·점 수 COMMON-001, 경로 COURSE-003·004·011, 이름 중복 006, 85% 유사 007, 일일 한도 008(429), "
                    + "출발점 지역 없음 009, 이미 등록한 기록 010.")
    @PostMapping("/gps")
    ApiResult<RegisteredCourse> registerGps(
            @AuthenticationPrincipal Jwt jwt,
            @Parameter(description = "등록 시도마다 앱이 만드는 UUID. 같은 등록을 재시도할 때는 같은 값") @RequestHeader("Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody RegisterGpsCourseRequest request) {
        return ApiResult.success(registrationService.registerGps(UUID.fromString(jwt.getSubject()), idempotencyKey, request));
    }

    @Operation(summary = "오늘 남은 등록 수와 GPS 등록에 쓴 기록",
            description = "유형별로 따로 센다: 사용자 지정 하루 1개, GPS(B5·B6 합산) 하루 3개. Asia/Seoul 00:00에 초기화. "
                    + "remaining이 0이면 앱은 해당 방식의 코스 만들기를 막고 안내한다(B4-07·B6-06). "
                    + "usedRunRecordIds는 GPS 코스 등록에 쓴 러닝 기록이다(코스가 지워져도 남는다, B6-04 `이미 등록됨`).")
    @GetMapping("/registration-quota")
    ApiResult<RegistrationQuota> quota(@AuthenticationPrincipal Jwt jwt) {
        return ApiResult.success(registrationService.quota(UUID.fromString(jwt.getSubject())));
    }
}

package com.wadadak.course.internal.mine;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

import static com.wadadak.course.internal.mine.MyCourseController.memberId;

@RestController
@RequestMapping("/api/v1/courses")
@RequiredArgsConstructor
// shortcut: 실제 구현 전이라 스텁을 켠 로컬 서버에서만 뜬다(공용 서버는 prod라 스텁을 막는다). 실제 구현 PR에서 이 조건을 지운다
@ConditionalOnProperty(name = "app.stub.course-mine", havingValue = "true")
class MyCourseEditController {

    private final MyCourseEditor editor;

    @Operation(summary = "코스 수정 (B7)",
            description = "이름 · 난이도 · 특징을 모두 보낸다(전체 교체). 경로 · 유형 · 만료일은 바뀌지 않고, 바꾼 값은 지도 · 목록 · 상세에 바로 보인다. "
                    + "응답은 바뀐 G4 카드 값이다. 이름 길이 · 형식 오류 COMMON-001, 내 코스가 아님 COMMON-003, 없는 코스 COURSE-001, "
                    + "삭제 예정 · 삭제된 코스 COURSE-002, 다른 공개 코스와 같은 이름(공백 · 대소문자 무시) COURSE-006. "
                    + "지금 이 코스 이름은 그대로 둬도 된다.")
    @PutMapping("/{courseId}")
    ApiResult<MyCourseItem> edit(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID courseId,
                                 @Valid @RequestBody EditCourseRequest request) {
        return ApiResult.success(editor.edit(memberId(jwt), courseId, request));
    }

    @Operation(summary = "코스 삭제 (B7)",
            description = "공개 중인 코스를 바로 비공개로 바꾸고 24시간 뒤 지운다(만료와 같다, 정책 공통 4). "
                    + "지도 · 목록 · 검색 · 상세와 새 러닝 시작은 바로 막히고, 이미 시작한 러닝과 개인 기록은 남는다. "
                    + "삭제되면 코스 통계 · 리뷰 · 랭킹도 지워진다. 응답은 삭제 예정으로 바뀐 G4 카드 값(status HIDDEN, "
                    + "statusReason USER_DELETED, deleteAt)이다. 이미 삭제 예정이면 바꾸지 않고 그 값을 돌려준다. "
                    + "내 코스가 아님 COMMON-003, 없는 코스 COURSE-001, 삭제가 끝난 코스 COURSE-002.")
    @DeleteMapping("/{courseId}")
    ApiResult<MyCourseItem> delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID courseId) {
        return ApiResult.success(editor.delete(memberId(jwt), courseId));
    }
}

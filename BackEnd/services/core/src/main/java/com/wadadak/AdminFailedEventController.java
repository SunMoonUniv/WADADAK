package com.wadadak;

import com.wadadak.AdminFailedEvents.Deleted;
import com.wadadak.AdminFailedEvents.Moved;
import com.wadadak.AdminFailedEvents.Row;
import com.wadadak.AdminFailedEvents.Service;
import com.wadadak.AdminFailedEvents.Stats;
import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 운영자 웹 "실패 이벤트"(DLQ). 운영자 계정(HTTP Basic)으로만 부른다(SecurityConfig의 /api/v1/admin/**).
 * <p>
 * 서비스 사이 이벤트 전체를 다루므로 어느 모듈에도 넣지 않고 EventBrokerConfig 옆(core의 맨 위 패키지)에 둔다.
 * service: CORE(core가 처리하지 못한 run 이벤트) · RUN(run이 처리하지 못한 core 이벤트).
 */
@RestController
@RequestMapping("/api/v1/admin/failed-events")
@RequiredArgsConstructor
class AdminFailedEventController {

    private final AdminFailedEvents failedEvents;

    @Operation(summary = "[운영자] 실패 이벤트 수", description = "core · run DLQ에 남은 메시지 수.")
    @GetMapping("/stats")
    ApiResult<Stats> stats() {
        return ApiResult.success(failedEvents.stats());
    }

    @Operation(summary = "[운영자] 실패 이벤트 목록",
            description = "DLQ 앞에서부터 최대 50개. 보기만 하고 큐에서 빼지 않는다. "
                    + "reason은 오류 메시지(재시도 없이 바로 거절된 메시지는 null), failedCount는 몇 번째로 DLQ에 왔는지.")
    @GetMapping
    ApiResult<List<Row>> list(@RequestParam Service service) {
        return ApiResult.success(failedEvents.list(service));
    }

    @Operation(summary = "[운영자] 실패 이벤트 모두 되돌리기",
            description = "DLQ의 메시지를 처음 왔던 exchange · 라우팅 키로 다시 보낸다. 원래 길을 모르는 메시지는 남긴다(skipped). "
                    + "원인을 고친 뒤에 부른다. 또 실패하면 약 6분 뒤 DLQ로 돌아온다.")
    @PostMapping("/{service}/redrive")
    ApiResult<Moved> redrive(@PathVariable Service service) {
        return ApiResult.success(failedEvents.redrive(service));
    }

    @Operation(summary = "[운영자] 실패 이벤트 모두 지우기", description = "DLQ를 비운다. 되돌릴 수 없다.")
    @PostMapping("/{service}/purge")
    ApiResult<Deleted> purge(@PathVariable Service service) {
        return ApiResult.success(failedEvents.purge(service));
    }
}

package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.PlanForm.Pref;

import java.util.List;
import java.util.Set;

/**
 * 코스 자동 생성 결과(A3 후보 또는 A6 · 폼 안내).
 *
 * @param candidates 후보 0~3개, 좋은 순. 0개면 reason이 있다
 * @param reason     후보가 없을 때만 이유. 후보가 있으면 null
 * @param message    reason에 맞는 안내 문구(정책 B3-A04). 앱은 그대로 보인다
 * @param startName  찾은 출발 장소 이름. 현재 위치 출발이면 null
 */
record PlanResult(List<PlanCandidate> candidates, PlanReason reason, String message, String startName) {

    static PlanResult failure(PlanReason reason, String message, String startName) {
        return new PlanResult(List.of(), reason, message, startName);
    }

    /**
     * 후보 하나.
     *
     * @param anchorPoints  B3 입력점으로 채울 점(최대 500개, 정책 B3-A08). 첫 점이 출발이다
     * @param retraceRatio  같은 길을 되돌아오는 비율(0~1)
     * @param arterialRatio 큰길(간선도로) 비율(0~1)
     * @param storeCount    경로 50m 안 편의점 수
     * @param summary       후보 카드 문구. 예: "5.14km · 큰길 24% · 편의점 3곳"
     * @param notApplied    요청한 원하는 길 중 아직 반영하지 않은 것
     */
    record PlanCandidate(List<GeoPoint> anchorPoints, int distanceMeters, double retraceRatio, double arterialRatio,
                         int storeCount, String summary, Set<Pref> notApplied) {

        static String summary(int distanceMeters, double arterialRatio, int storeCount) {
            return "%.2fkm · 큰길 %d%% · 편의점 %d곳".formatted(distanceMeters / 1000.0, Math.round(arterialRatio * 100), storeCount);
        }
    }

    enum PlanReason {
        /** 출발 · 도착 · 경유 장소를 찾지 못했다 */
        PLACE_NOT_FOUND,
        /** 도착 · 경유지가 목표 거리에 비해 너무 멀다 */
        PLACE_TOO_FAR,
        /** 길을 따라 후보를 만들지 못했다(섬 · 산간 · 짧은 한 바퀴). 한 바퀴면 왕복을 제안한다 */
        NO_CANDIDATES,
        /** 만든 후보가 모두 기존 코스와 85% 이상 겹친다 */
        SIMILAR_EXISTS
    }
}

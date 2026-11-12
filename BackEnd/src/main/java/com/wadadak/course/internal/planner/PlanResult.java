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
 * @param notApplied 요청한 원하는 길 중 아직 반영하지 않은 것. 후보가 없으면 비어 있다
 */
record PlanResult(List<PlanCandidate> candidates, PlanReason reason, String message, String startName, Set<Pref> notApplied) {

    static PlanResult found(List<PlanCandidate> candidates, String startName, Set<Pref> notApplied) {
        return new PlanResult(candidates, null, null, startName, notApplied);
    }

    static PlanResult failure(PlanReason reason, String message, String startName) {
        return new PlanResult(List.of(), reason, message, startName, Set.of());
    }

    // 안내 문구(정책 B3-A04). 스텁과 실제 구현이 같이 쓴다

    static PlanResult placeNotFound(String query, String startName) {
        return failure(PlanReason.PLACE_NOT_FOUND,
                "'%s'%s 찾지 못했어요. 이름을 다시 확인해 주세요.".formatted(query, particle(query, "을", "를")), startName);
    }

    /** @param from 출발 장소 이름. 현재 위치 출발이면 "현재 위치" */
    static PlanResult placeTooFar(String query, String from, double meters, String startName) {
        return failure(PlanReason.PLACE_TOO_FAR, "%s%s %s에서 약 %dkm 떨어져 있어요. 가까운 곳을 골라 주세요."
                .formatted(query, particle(query, "은", "는"), from, Math.max(1, Math.round(meters / 1000))), startName);
    }

    static PlanResult noCandidates(boolean suggestOutAndBack, String startName) {
        return failure(PlanReason.NO_CANDIDATES, suggestOutAndBack
                ? "이 근처에서는 길을 따라 한 바퀴 코스를 만들지 못했어요. 왕복으로 바꿔 보세요."
                : "이 근처에서는 길을 따라 코스를 만들지 못했어요.", startName);
    }

    static PlanResult similarExists(String startName) {
        return failure(PlanReason.SIMILAR_EXISTS, "비슷한 코스가 이미 있어요. 거리나 출발지를 바꿔 보세요.", startName);
    }

    /** 끝 글자에 받침이 있으면 withFinal, 없으면 withoutFinal. 한글로 끝나지 않으면 "을(를)"처럼 둘 다 */
    private static String particle(String word, String withFinal, String withoutFinal) {
        char last = word.charAt(word.length() - 1);
        if (last < '가' || last > '힣') {
            return withFinal + "(" + withoutFinal + ")";
        }
        return (last - '가') % 28 != 0 ? withFinal : withoutFinal;
    }

    /**
     * 후보 하나.
     *
     * @param anchorPoints  B3 입력점으로 채울 점(최대 500개, 정책 B3-A08). 첫 점이 출발이다
     * @param retraceRatio  같은 길을 되돌아오는 비율(0~1)
     * @param arterialRatio 큰길(간선도로) 비율(0~1)
     * @param storeCount    경로 50m 안 편의점 수
     * @param toiletCount   경로 100m 안 공중화장실 수
     * @param ascentMeters  경로를 따라 오른 높이(m). 표고점 파일이 없거나 높이를 모르는 곳이 많으면 null
     */
    record PlanCandidate(List<GeoPoint> anchorPoints, int distanceMeters, double retraceRatio, double arterialRatio,
                         int storeCount, int toiletCount, Integer ascentMeters) {
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

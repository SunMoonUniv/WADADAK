package com.wadadak.run.internal.judging;

/**
 * 서버 코스 판정 기준값(정책 제3부 5.3). 이탈 안내 기준(30m·10초·20m)은 앱 전용이라 여기 없다.
 *
 * @param routeToleranceM  경로 일치 허용 오차. 경로까지 거리가 이 값 이하인 표본만 경로 위로 본다
 * @param startRadiusM     출발 확인 반경. 첫 표본이 출발점에서 이 거리 안이어야 한다
 * @param finishToleranceM 끝 도달 오차. 코스상 위치가 전체 길이에서 이 거리 안이면 끝 도달
 * @param maxSpeedMps      이동 속도 상한(m/s). 두 표본 사이가 이보다 빠르면 그 사이를 인정하지 않는다
 */
record JudgingConfig(double routeToleranceM, double startRadiusM, double finishToleranceM, double maxSpeedMps) {

    // ponytail: 주행 검증 전 개발용 값. 속도 상한은 1번 GPS 품질 기본값(12m/s)과 같다. 확정되면 설정 파일로 옮긴다
    static final JudgingConfig DEFAULTS = new JudgingConfig(20, 30, 30, 12);
}

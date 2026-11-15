package com.wadadak.run.internal;

import com.wadadak.run.internal.RunContracts.Input;

/**
 * 러닝 GPS 입력 품질 기준. 자유 러닝 거리(metrics)와 코스 판정(judging)이 같은 기준을 쓴다.
 * 값은 1번 입력 계약의 GPS 품질 기본값이다. 개발용이며 실주행 보정 전이다.
 */
public final class GpsQuality {

    /** 정확도 상한(m). 이보다 나쁜 표본은 거리·판정에 쓰지 않는다 */
    public static final double MAX_ACCURACY_M = 30;
    /** 두 GPS 표본 사이 속도 상한(m/s). 넘으면 그 사이를 잇지 않는다 */
    public static final double MAX_SPEED_MPS = 12;
    /** 두 GPS 표본 사이 간격 상한(ms). 넘으면 그 사이를 잇지 않는다 */
    public static final long MAX_INTERVAL_MS = 10_000;

    private GpsQuality() {
    }

    /** 위치가 있고 정확도가 0 ~ {@link #MAX_ACCURACY_M}인 GPS 표본 */
    public static boolean good(Input p) {
        return p.location() != null && p.accuracyM() != null && Double.isFinite(p.accuracyM())
                && p.accuracyM() >= 0 && p.accuracyM() <= MAX_ACCURACY_M;
    }
}

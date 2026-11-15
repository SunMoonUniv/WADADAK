package com.wadadak.run.internal.judging;

import com.wadadak.run.internal.judging.CourseTracker.Point;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * 판정 4단계 — 코스 인정 거리(정책 제3부 4.2). 연결된 두 표본 사이에서 s가 늘어난 구간 [s1, s2]만 인정하고,
 * 구간들을 합집합으로 합쳐 같은 구간은 한 번만 센다. 역방향·끊긴 사이(코스 밖·점프·정지·공백)는 들어가지 않는다.
 *
 * @param ranges   합친 인정 범위, from 오름차순·겹치지 않음
 * @param meters   인정 거리(m) = 범위 길이의 합
 * @param timeline 표본마다 그 시점까지의 인정 거리. 완주 조건을 처음 충족한 시점을 찾는 데 쓴다(5단계)
 */
record RecognizedDistance(List<Range> ranges, double meters, List<Progress> timeline) {

    /** 코스상 위치 from ~ to(m) */
    record Range(double from, double to) {
        double length() {
            return to - from;
        }
    }

    /** {@code point}까지 달렸을 때의 누적 인정 거리 */
    record Progress(Point point, double recognizedM) {
    }

    static RecognizedDistance of(List<Point> points) {
        List<Range> ranges = new ArrayList<>();
        List<Progress> timeline = new ArrayList<>();
        double meters = 0;
        Point previous = null;
        for (Point point : points) {
            if (previous != null && point.connected()
                    && previous.s() != null && point.s() != null && point.s() > previous.s()) {
                meters = merge(ranges, new Range(previous.s(), point.s()));
            }
            timeline.add(new Progress(point, meters));
            previous = point;
        }
        return new RecognizedDistance(List.copyOf(ranges), meters, List.copyOf(timeline));
    }

    /**
     * 범위를 넣고 겹치거나 맞닿은 것끼리 합친 뒤 전체 길이를 돌려준다.
     * 연속 주행이면 마지막 범위에 계속 붙어 범위 수가 작게 유지된다.
     */
    private static double merge(List<Range> ranges, Range added) {
        ranges.add(added);
        ranges.sort(Comparator.comparingDouble(Range::from));
        List<Range> merged = new ArrayList<>();
        for (Range range : ranges) {
            if (!merged.isEmpty() && range.from() <= merged.getLast().to()) {
                Range last = merged.removeLast();
                merged.add(new Range(last.from(), Math.max(last.to(), range.to())));
            } else {
                merged.add(range);
            }
        }
        ranges.clear();
        ranges.addAll(merged);
        return merged.stream().mapToDouble(Range::length).sum();
    }
}

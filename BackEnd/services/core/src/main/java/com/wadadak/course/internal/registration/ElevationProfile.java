package com.wadadak.course.internal.registration;

import com.wadadak.common.geo.GeoPoint;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * 코스의 고도 프로필(B1-03). GPS 코스는 등록에 쓴 러닝 기록의 GPS 고도로 등록 때 한 번 만들어 저장한다(정책 공통 3).
 * 그린 코스와 등록 기록에 고도가 부족했던 GPS 코스는 고도가 충분한 첫 완주 경로로 한 번 만든다({@link ElevationProfileEventHandler}).
 * 기준은 정책 문서 제4부 4.1 `B1-03 고도 프로필`이다. 최저 고도는 휴대폰마다 GPS 고도의 기준이 달라 두지 않는다.
 *
 * @param gainMeters    누적 상승(m). 골짜기에서 10m 이상 오른 것만 센다
 * @param samplesMeters 출발점부터 코스를 거리로 18칸 나눈 칸마다의 평균 고도(m). 막대 높이를 서로 견주는 데만 쓴다
 */
public record ElevationProfile(int gainMeters, List<Double> samplesMeters) {

    /** 막대 수(Figma B1) */
    static final int BARS = 18;

    /** 칸마다 평균을 내려고 고도를 읽는 수 */
    private static final int READS_PER_BAR = 20;

    /** 고도 정확도가 이보다 나쁜 점은 쓰지 않는다(m). 달리기 상승 고도와 같다 */
    private static final double MAX_ACCURACY_M = 20;

    /** 이웃 점과 높이가 max(이 값, 두 점 고도 정확도 합)보다 크게 다르면 튄 것으로 보고 높이를 잇지 않는다(m). 달리기와 같다 */
    private static final double JUMP_M = 10;

    /** 골짜기에서 이만큼 오르면 오르막이고, 오르는 중 봉우리에서 이만큼 내려가면 그 오르막을 더한다(m) */
    private static final double CLIMB_M = 10;

    /** 고도를 잰 거리가 코스 길이의 이 비율보다 적으면 프로필이 없다 */
    private static final double MIN_COVERAGE = 0.9;

    /**
     * @param segments 앱이 보낸 경로 조각(course-source)이나 run이 보낸 완주 경로 조각. 조각 사이 빈칸은 코스 경로처럼 직선으로 이어 거리를 센다
     * @return 고도를 잰 거리가 이 경로 길이의 90%보다 적으면 null
     */
    static ElevationProfile of(List<List<GpsSourcePoint>> segments) {
        // 높이를 이어 잰 구간들. 조각이 끊긴 곳 · 고도가 없거나 튄 곳에서 나눈다
        List<List<Height>> runs = new ArrayList<>();
        double distance = 0;
        GeoPoint previous = null;
        for (List<GpsSourcePoint> segment : segments) {
            List<Height> run = new ArrayList<>();
            GpsSourcePoint last = null;
            for (GpsSourcePoint point : segment) {
                GeoPoint at = point.location();
                distance += previous == null ? 0 : previous.distanceMeters(at);
                previous = at;
                if (!usable(point) || (last != null && jumps(last, point))) {
                    keep(run, runs);
                    run = new ArrayList<>();
                    last = null;
                }
                if (usable(point)) {
                    run.add(new Height(distance, point.altitudeM()));
                    last = point;
                }
            }
            keep(run, runs);
        }
        double measured = runs.stream().mapToDouble(run -> run.getLast().distanceM() - run.getFirst().distanceM()).sum();
        if (distance <= 0 || measured < distance * MIN_COVERAGE) {
            return null;
        }

        double gain = runs.stream().mapToDouble(ElevationProfile::gain).sum();
        List<Height> heights = runs.stream().flatMap(List::stream).toList();
        double[] at = heights.stream().mapToDouble(Height::distanceM).toArray();
        double[] height = heights.stream().mapToDouble(Height::heightM).toArray();
        List<Double> samples = new ArrayList<>(BARS);
        for (int bar = 0; bar < BARS; bar++) {
            double sum = 0;
            for (int read = 0; read < READS_PER_BAR; read++) {
                sum += heightAt(at, height, (bar * READS_PER_BAR + read + 0.5) * distance / (BARS * READS_PER_BAR));
            }
            samples.add(Math.round(sum / READS_PER_BAR * 10) / 10.0);
        }
        return new ElevationProfile((int) Math.round(gain), List.copyOf(samples));
    }

    /** 고도가 있고 고도 정확도가 20m 이하다. 정확도를 모르면 쓴다 */
    private static boolean usable(GpsSourcePoint point) {
        Double accuracy = point.altitudeAccuracyM();
        return point.altitudeM() != null && Double.isFinite(point.altitudeM())
                && (accuracy == null || accuracy <= MAX_ACCURACY_M);
    }

    private static boolean jumps(GpsSourcePoint before, GpsSourcePoint after) {
        double allowed = Math.max(JUMP_M, accuracy(before) + accuracy(after));
        return Math.abs(after.altitudeM() - before.altitudeM()) > allowed;
    }

    private static double accuracy(GpsSourcePoint point) {
        return point.altitudeAccuracyM() == null ? 0 : point.altitudeAccuracyM();
    }

    /** 점이 3개 이상인 구간만 쓴다(달리기와 같다). 5개 점(앞뒤 2개씩) 중앙값으로 고른다. 1초에 한 점쯤이라 달리기의 5초 중앙값과 같은 폭이다 */
    private static void keep(List<Height> run, List<List<Height>> runs) {
        if (run.size() < 3) {
            return;
        }
        List<Height> smoothed = new ArrayList<>(run.size());
        for (int i = 0; i < run.size(); i++) {
            double[] window = run.subList(Math.max(0, i - 2), Math.min(run.size(), i + 3)).stream()
                    .mapToDouble(Height::heightM).sorted().toArray();
            int middle = window.length / 2;
            double median = window.length % 2 == 1 ? window[middle] : (window[middle - 1] + window[middle]) / 2;
            smoothed.add(new Height(run.get(i).distanceM(), median));
        }
        runs.add(smoothed);
    }

    /** 골짜기에서 10m 이상 오르면 오르막이다. 그 뒤 봉우리에서 10m 이상 내려가거나 구간이 끝나면 골짜기부터 봉우리까지를 더한다 */
    private static double gain(List<Height> run) {
        double total = 0;
        double valley = run.getFirst().heightM();
        double peak = valley;
        boolean rising = false;
        for (Height point : run) {
            double h = point.heightM();
            if (!rising) {
                valley = Math.min(valley, h);
                rising = h - valley >= CLIMB_M;
                peak = h;
            } else if (h > peak) {
                peak = h;
            } else if (peak - h >= CLIMB_M) {
                total += peak - valley;
                valley = h;
                rising = false;
            }
        }
        return rising ? total + peak - valley : total;
    }

    /** 거리 [x]의 높이. 잰 점 사이(못 잰 곳 포함)는 직선으로 잇고, 처음 · 마지막 점 바깥은 그 점 높이다 */
    private static double heightAt(double[] at, double[] height, double x) {
        int found = Arrays.binarySearch(at, x);
        if (found >= 0) {
            return height[found];
        }
        int next = -found - 1;
        if (next == 0) {
            return height[0];
        }
        if (next == at.length) {
            return height[at.length - 1];
        }
        double t = (x - at[next - 1]) / (at[next] - at[next - 1]);
        return height[next - 1] + t * (height[next] - height[next - 1]);
    }

    /** 출발점부터 거리(m)와 그 점 높이(m) */
    private record Height(double distanceM, double heightM) {
    }
}

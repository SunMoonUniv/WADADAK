package com.wadadak.run.internal.metrics;

import com.wadadak.common.exception.AppException;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.metrics.RunResultStatsCalculator.ElevationBlock;
import com.wadadak.run.internal.metrics.RunResultStatsCalculator.ElevationPoint;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * 구간 분석(D3·D5·D6): 저장된 1 km 랩마다 케이던스·고도. 랩 경계(경과 시간)로 원본을 나눠 요청 때 계산한다.
 * 결과의 거리·시간·랩은 바꾸지 않는다.
 */
public final class SplitCalculator {
    public static final String VERSION = "SPLITS_V1";
    /** 고도 변화를 보이려면 랩 이동시간 중 고도로 이어진 시간이 이만큼 있어야 한다(초기값, 주행 검증 전) */
    private static final double ELEVATION_COVERAGE = .9;

    private SplitCalculator() {}

    public static Splits calculate(Instant startedAt, List<Input> inputs, List<Lap> laps) {
        FreeRunCalculator.Calculation run;
        try { run = FreeRunCalculator.calculate(startedAt, inputs); }
        catch (AppException e) { // 지금 규칙으로 계산되지 않는 원본: 랩 번호만 두고 값은 비운다
            return new Splits(VERSION, laps.stream().map(l -> new Split(l.number(), null, null, null)).toList());
        }
        List<ElevationBlock> blocks = RunResultStatsCalculator.elevationBlocks(inputs,
            RunResultStatsCalculator.analysisSegments(inputs, run.samples())).stream().flatMap(List::stream).toList();
        List<Split> splits = new ArrayList<>();
        Double[] gain = new Double[laps.size()];
        long start = 0;
        for (int i = 0; i < laps.size(); i++) {
            Lap lap = laps.get(i);
            long end = start + lap.elapsedMs();
            // 마지막 랩은 기록 전체로 계산해 결과 상승 고도와 맞춘다
            gain[i] = gainUntil(inputs, run.samples(), i == laps.size() - 1 ? Long.MAX_VALUE : end);
            splits.add(new Split(lap.number(), cadence(run.cadence(), start, end), change(blocks, start, end, lap.movingMs()), null));
            start = end;
        }
        // ponytail: 랩 끝마다 앞부분만 다시 계산(랩 수 × 원본). 뒤 자료로 앞 상승이 취소되면 줄어들 수 있어 뒤 랩보다 크지 않게 맞춘다
        Double next = null;
        for (int i = laps.size() - 1; i >= 0; i--) {
            if (gain[i] != null && next != null && gain[i] > next) gain[i] = next;
            if (gain[i] != null) next = gain[i];
            Split s = splits.get(i);
            splits.set(i, new Split(s.number(), s.cadence(), s.elevationChangeM(), gain[i]));
        }
        return new Splits(VERSION, List.copyOf(splits));
    }

    /** 랩 시간에 걸친 걸음 표본은 시간 비율로 나눈다 */
    private static Double cadence(List<Input> samples, long start, long end) {
        double steps = 0;
        long covered = 0;
        for (Input p : samples) {
            long sampleEnd = p.sampleEndMs() == null ? p.elapsedMs() : p.sampleEndMs();
            long overlap = Math.min(sampleEnd, end) - Math.max(sampleEnd - p.durationMs(), start);
            if (overlap <= 0) continue;
            steps += p.steps() * (double) overlap / p.durationMs();
            covered += overlap;
        }
        return covered > 0 ? steps * 60000 / covered : null;
    }

    /** 고도 덩어리마다 랩 안의 끝 높이 − 시작 높이를 더한다(덩어리 사이는 잇지 않는다) */
    private static Double change(List<ElevationBlock> blocks, long start, long end, long movingMs) {
        double change = 0;
        long covered = 0;
        for (ElevationBlock b : blocks) {
            List<ElevationPoint> points = b.points();
            long from = Math.max(start, points.getFirst().elapsedMs()), to = Math.min(end, points.getLast().elapsedMs());
            if (to <= from) continue;
            change += heightAt(points, to) - heightAt(points, from);
            covered += to - from;
        }
        return covered > 0 && covered >= movingMs * ELEVATION_COVERAGE ? change : null;
    }

    /** 상승 고도와 같은 중앙 5초 중앙값. 그 안에 표본이 없으면 가장 가까운 표본 */
    private static double heightAt(List<ElevationPoint> points, long ms) {
        List<Double> window = new ArrayList<>();
        ElevationPoint nearest = points.getFirst();
        for (ElevationPoint p : points) {
            if (Math.abs(p.elapsedMs() - ms) <= 2500) window.add(p.height());
            if (Math.abs(p.elapsedMs() - ms) < Math.abs(nearest.elapsedMs() - ms)) nearest = p;
        }
        if (window.isEmpty()) return nearest.height();
        window.sort(null);
        int m = window.size() / 2;
        return window.size() % 2 == 1 ? window.get(m) : (window.get(m - 1) + window.get(m)) / 2;
    }

    private static Double gainUntil(List<Input> inputs, List<List<Input>> samples, long ms) {
        if (ms == Long.MAX_VALUE) return RunResultStatsCalculator.calculate(inputs, samples, List.of()).elevationGainM();
        List<Input> head = inputs.stream().filter(p -> p.elapsedMs() <= ms).toList();
        List<List<Input>> segments = samples.stream()
            .map(s -> s.stream().filter(p -> p.elapsedMs() <= ms).toList()).filter(s -> !s.isEmpty()).toList();
        return RunResultStatsCalculator.calculate(head, segments, List.of()).elevationGainM();
    }
}

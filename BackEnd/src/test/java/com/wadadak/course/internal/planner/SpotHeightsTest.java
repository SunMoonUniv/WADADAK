package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.SpotHeights.Grid;
import org.junit.jupiter.api.Test;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static com.wadadak.course.internal.planner.CandidateGenerator.destination;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class SpotHeightsTest {

    private static final GeoPoint START = new GeoPoint(36.80, 127.07);

    @Test
    void projectsToKorea2000() {
        // EPSG:5179 원점(38N, 127.5E)
        double[] origin = SpotHeights.tm5179(new GeoPoint(38.0, 127.5));
        assertThat(origin[0]).isCloseTo(1_000_000, within(0.01));
        assertThat(origin[1]).isCloseTo(2_000_000, within(0.01));
        double[] cityHall = SpotHeights.tm5179(new GeoPoint(37.5663, 126.9779));
        assertThat(cityHall[0]).isBetween(953_000.0, 955_000.0);
        assertThat(cityHall[1]).isBetween(1_951_000.0, 1_953_000.0);
    }

    @Test
    void addsUpClimbOnSlope() {
        // 북쪽으로 5% 오르는 평면에 100m마다 표고점
        SpotHeights heights = new SpotHeights(slope(0.05));
        List<GeoPoint> north = line(START, 0, 1_000);
        List<GeoPoint> there = new ArrayList<>(north);
        there.addAll(north.reversed());

        // 50m마다 찍은 0~950m 중 양 끝 점은 다듬기에서 빠진다: 50~900m, 850m × 5%
        assertThat(heights.ascentMeters(north)).isCloseTo(43, within(1));
        // 내려오는 길은 더하지 않는다(꼭대기 1,000m까지 올라 조금 더 크다)
        assertThat(heights.ascentMeters(there)).isCloseTo(46, within(1));
        assertThat(heights.ascentMeters(line(START, 90, 1_000))).isLessThanOrEqualTo(1);
    }

    @Test
    void unknownWhenMostOfRouteHasNoSpotHeights() {
        SpotHeights heights = new SpotHeights(slope(0.05));

        // 표고점은 출발점 둘레 3km 안에만 있다
        assertThat(heights.ascentMeters(line(destination(START, 2_000, 0), 0, 3_000))).isNull();
        assertThat(new SpotHeights("../build/없는 파일.bin").available()).isFalse();
        assertThat(new SpotHeights("../build/없는 파일.bin").ascentMeters(line(START, 0, 1_000))).isNull();
    }

    /** 로컬에 utilfile 표고점 파일이 있으면, 만든 스크립트(Python)로 구한 스텁 후보 오르막과 같은지 본다 */
    @Test
    void matchesBuildScriptOnRealFile() throws Exception {
        String file = "../utilfile/elevation/spot_heights.bin";
        assumeTrue(Files.isRegularFile(Path.of(file)));
        SpotHeights heights = new SpotHeights(file);
        List<Map<String, Object>> routes;
        try (InputStream in = getClass().getResourceAsStream("/planner/stub-candidates.json")) {
            routes = JsonMapper.builder().build().readValue(in, new TypeReference<>() {
            });
        }

        for (Map<String, Object> route : routes) {
            @SuppressWarnings("unchecked")
            List<Map<String, Double>> points = (List<Map<String, Double>>) route.get("anchorPoints");
            List<GeoPoint> line = points.stream().map(p -> new GeoPoint(p.get("lat"), p.get("lng"))).toList();
            assertThat(heights.ascentMeters(line)).isEqualTo(route.get("ascentMeters"));
        }
    }

    /** 출발점에서 heading 쪽으로 meters, 50m마다 점 */
    private static List<GeoPoint> line(GeoPoint from, int heading, int meters) {
        List<GeoPoint> points = new ArrayList<>();
        for (int d = 0; d <= meters; d += 50) {
            points.add(destination(from, d, heading));
        }
        return points;
    }

    /** 출발점 둘레 3km × 3km, 100m마다 z = 100 + grade × (북쪽 거리) */
    private static Grid slope(double grade) {
        double[] origin = SpotHeights.tm5179(START);
        List<double[]> spots = new ArrayList<>();
        for (int dx = -1_500; dx <= 1_500; dx += 100) {
            for (int dy = -1_500; dy <= 1_500; dy += 100) {
                spots.add(new double[]{origin[0] + dx, origin[1] + dy, 100 + grade * dy});
            }
        }
        return grid(spots, 500);
    }

    /** build_spot_heights.py와 같은 형식으로 써서 읽는다 */
    private static Grid grid(List<double[]> spots, double cell) {
        double x0 = Math.floor(spots.stream().mapToDouble(s -> s[0]).min().orElseThrow() / cell) * cell;
        double y0 = Math.floor(spots.stream().mapToDouble(s -> s[1]).min().orElseThrow() / cell) * cell;
        int cols = (int) ((spots.stream().mapToDouble(s -> s[0]).max().orElseThrow() - x0) / cell) + 1;
        int rows = (int) ((spots.stream().mapToDouble(s -> s[1]).max().orElseThrow() - y0) / cell) + 1;
        List<List<double[]>> cells = new ArrayList<>();
        for (int i = 0; i < cols * rows; i++) {
            cells.add(new ArrayList<>());
        }
        for (double[] s : spots) {
            cells.get((int) ((s[1] - y0) / cell) * cols + (int) ((s[0] - x0) / cell)).add(s);
        }
        int n = spots.size();
        ByteBuffer b = ByteBuffer.allocate(44 + (cols * rows + 1) * 4 + n * 12).order(ByteOrder.LITTLE_ENDIAN);
        b.put("WDSH".getBytes(StandardCharsets.US_ASCII)).putInt(1).putDouble(x0).putDouble(y0).putDouble(cell)
                .putInt(cols).putInt(rows).putInt(n);
        int start = 0;
        for (List<double[]> c : cells) {
            b.putInt(start);
            start += c.size();
        }
        b.putInt(start);
        for (int axis = 0; axis < 3; axis++) {
            for (List<double[]> c : cells) {
                for (double[] s : c) {
                    b.putFloat((float) s[axis]);
                }
            }
        }
        return Grid.read(b.flip());
    }
}

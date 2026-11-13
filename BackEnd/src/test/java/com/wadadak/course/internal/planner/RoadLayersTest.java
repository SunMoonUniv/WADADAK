package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.RoadLayers.CellSet;
import com.wadadak.course.internal.planner.RoadLayers.Layer;
import org.junit.jupiter.api.Test;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

import static com.wadadak.course.internal.planner.CandidateGenerator.destination;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class RoadLayersTest {

    private static final GeoPoint START = new GeoPoint(36.7983, 127.0746);

    @Test
    void cellSetLooksAtTheCellAndItsEightNeighbours() {
        // 25m 칸. (열 10, 행 4) 하나만 표시
        CellSet set = CellSet.of(25, CellSet.key(10, 4));

        assertThat(set.near(260, 110)).isTrue();   // 같은 칸
        assertThat(set.near(230, 80)).isTrue();    // 대각선 이웃 칸(열 9, 행 3)
        assertThat(set.near(310, 110)).isFalse();  // 두 칸 옆(열 12)
        assertThat(set.near(260, 160)).isFalse();  // 두 칸 위(행 6)
    }

    @Test
    void readsFileWrittenByBuildScript() {
        ByteBuffer file = ByteBuffer.allocate(20 + 2 * Long.BYTES).order(ByteOrder.LITTLE_ENDIAN);
        file.put("WDCS".getBytes(StandardCharsets.US_ASCII)).putInt(1).putDouble(20).putInt(2)
                .putLong(CellSet.key(3, 1)).putLong(CellSet.key(7, 2)).flip();

        CellSet set = CellSet.read(file);

        assertThat(set.cell()).isEqualTo(20);
        assertThat(set.near(70, 30)).isTrue();
        assertThat(set.near(150, 50)).isTrue();
        assertThat(set.near(400, 400)).isFalse();
    }

    @Test
    void ratioIsTheShareOfRouteNearTheLayer() {
        // 출발점에서 동쪽으로 1km 가는 길의 앞 절반(500m)을 따라 칸을 표시한다
        RoadLayers layers = new RoadLayers(Map.of(Layer.RIVER, along(START, 500)));
        List<GeoPoint> route = List.of(START, destination(START, 1_000, 90));

        assertThat(layers.ratio(Layer.RIVER, route)).isCloseTo(0.5, within(0.1));
        assertThat(layers.ratio(Layer.SIDEWALK, route)).isNull();
        assertThat(layers.available(Layer.RIVER)).isTrue();
        assertThat(layers.available(Layer.LAMPS)).isFalse();
    }

    @Test
    void snapMovesPointToTheLayerWithinRadius() {
        RoadLayers layers = new RoadLayers(Map.of(Layer.RIVER, along(START, 500)));
        GeoPoint north = destination(START, 300, 0);

        GeoPoint snapped = layers.snap(Layer.RIVER, north, 400);

        // 북쪽 300m 점이 표시된 길(출발점에서 동쪽) 가까이로 온다
        assertThat(snapped).isNotEqualTo(north);
        assertThat(layers.ratio(Layer.RIVER, List.of(snapped, destination(snapped, 1, 90)))).isEqualTo(1.0);
        // 반경 안에 없으면, 이미 가까우면, 파일이 없으면 그대로
        assertThat(layers.snap(Layer.RIVER, north, 100)).isEqualTo(north);
        assertThat(layers.snap(Layer.RIVER, START, 400)).isEqualTo(START);
        assertThat(layers.snap(Layer.LAMPS, north, 400)).isEqualTo(north);
    }

    @Test
    void areaCoversTheLayerWithMergedRectangles() {
        // 출발점에서 동쪽으로 500m 가는 하천 띠
        RoadLayers layers = new RoadLayers(Map.of(Layer.RIVER, along(START, 500)));

        List<List<List<List<Double>>>> area = layers.area(Layer.RIVER, START, 1_000);

        // 띠는 25m마다 찍어도 줄마다 한 칸으로 합쳐져 직사각형이 몇 개뿐이다
        assertThat(area).isNotNull().hasSizeLessThan(5);
        assertThat(area).allSatisfy(polygon -> assertThat(polygon.getFirst()).hasSize(5).first().isEqualTo(polygon.getFirst().getLast()));
        assertThat(inside(area, destination(START, 250, 90))).isTrue();
        assertThat(inside(area, destination(START, 300, 0))).isFalse();
        assertThat(inside(area, destination(START, 800, 90))).isFalse();
        assertThat(layers.area(Layer.LAMPS, START, 1_000)).isNull();
        assertThat(layers.area(Layer.RIVER, destination(START, 5_000, 180), 1_000)).isNull();
    }

    /** [경도, 위도] 직사각형 중 하나에 든다 */
    private static boolean inside(List<List<List<List<Double>>>> area, GeoPoint p) {
        return area.stream().map(List::getFirst).anyMatch(ring -> {
            double west = ring.get(0).get(0), south = ring.get(0).get(1), east = ring.get(2).get(0), north = ring.get(2).get(1);
            return p.lng() >= west && p.lng() <= east && p.lat() >= south && p.lat() <= north;
        });
    }

    /** 실제 파일이 있을 때만: 한강 위는 하천이고, 종로는 인도 · 가로등이 있고, 북한산에는 둘 다 없다 */
    @Test
    void realFilesKnowTheHanRiverAndJongno() {
        Path dir = Path.of(System.getenv().getOrDefault("PLANNER_LAYERS_DIR", "../utilfile/layers"));
        assumeTrue(Files.isRegularFile(dir.resolve("river.bin")) && Files.isRegularFile(dir.resolve("sidewalk.bin"))
                && Files.isRegularFile(dir.resolve("lamps.bin")));
        RoadLayers layers = new RoadLayers(dir.toString());
        GeoPoint hanRiver = new GeoPoint(37.5172, 126.9960);   // 반포대교 아래 한강
        GeoPoint jongno = new GeoPoint(37.5701, 126.9800);
        GeoPoint mountain = new GeoPoint(37.6590, 126.9770);

        assertThat(layers.ratio(Layer.RIVER, around(hanRiver))).isEqualTo(1.0);
        assertThat(layers.ratio(Layer.RIVER, around(jongno))).isEqualTo(0.0);
        assertThat(layers.ratio(Layer.SIDEWALK, around(jongno))).isGreaterThan(0.5);
        assertThat(layers.ratio(Layer.LAMPS, around(jongno))).isGreaterThan(0.5);
        assertThat(layers.ratio(Layer.SIDEWALK, around(mountain))).isEqualTo(0.0);
        assertThat(layers.ratio(Layer.LAMPS, around(mountain))).isEqualTo(0.0);
    }

    /** 점에서 동쪽으로 100m 가는 길 */
    private static List<GeoPoint> around(GeoPoint p) {
        return List.of(p, destination(p, 100, 90));
    }

    /** from에서 동쪽으로 meters만큼, 10m마다 25m 칸을 표시한 집합 */
    private static CellSet along(GeoPoint from, int meters) {
        long[] keys = java.util.stream.IntStream.rangeClosed(0, meters / 10)
                .mapToObj(i -> SpotHeights.tm5179(destination(from, 10.0 * i, 90)))
                .mapToLong(xy -> CellSet.key((long) Math.floor(xy[0] / 25), (long) Math.floor(xy[1] / 25)))
                .distinct().sorted().toArray();
        return CellSet.of(25, keys);
    }
}

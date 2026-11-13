package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.LongBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/**
 * 인도 · 강변 · 밝은 길 조건에 쓰는 전국 칸 집합({@code app.course.planner.layers-dir}의 sidewalk.bin · river.bin · lamps.bin).
 * 칸은 EPSG:5179 격자이고, 인도 선이 지나는 20m 칸 · 하천 면에 든 25m 칸 · 가로등이나 보안등이 있는 20m 칸을 표시해 둔 것이다.
 * 점이 든 칸과 둘레 8칸 중 하나라도 표시돼 있으면 그 점은 가깝다(인도 · 등 약 20~40m, 하천 25~50m 안).
 * 파일은 {@code utilfile/_스크립트/course_planner/build_layers.py}가 만든다(형식은 그 설명). 파일이 없는 조건은 서버가 그대로 뜨고
 * 반영하지 않는다(후보의 notApplied).
 */
@Slf4j
@Component
class RoadLayers {

    enum Layer {
        SIDEWALK, RIVER, LAMPS;

        String fileName() {
            return name().toLowerCase() + ".bin";
        }
    }

    /** 경로를 이 간격(m)으로 다시 찍어 가까운 점의 비율을 구한다 */
    static final double STEP_METERS = 25;
    /** {@link #snap}이 둘레를 찾는 간격(m) · 방향(도) */
    private static final double SNAP_STEP_METERS = 50;
    private static final int SNAP_BEARING_STEP = 30;

    /** 파일이 있는 것만 든다 */
    private final Map<Layer, CellSet> sets;

    @Autowired
    RoadLayers(@Value("${app.course.planner.layers-dir}") String dir) {
        this(load(Path.of(dir)));
    }

    RoadLayers(Map<Layer, CellSet> sets) {
        this.sets = sets;
    }

    boolean available(Layer layer) {
        return sets.containsKey(layer);
    }

    /** 경로 중 layer 가까이 지나는 비율(0~1). 파일이 없으면 null */
    Double ratio(Layer layer, List<GeoPoint> route) {
        CellSet set = sets.get(layer);
        if (set == null) {
            return null;
        }
        List<double[]> samples = RouteMetrics.resample(route.stream().map(SpotHeights::tm5179).toList(), STEP_METERS);
        if (samples.isEmpty()) {
            return 0.0;
        }
        return (double) samples.stream().filter(s -> set.near(s[0], s[1])).count() / samples.size();
    }

    /**
     * point에서 radiusMeters 안의 layer 가까운 점. point가 이미 가까우면 그대로, 없으면(파일이 없을 때도) point를 돌려준다.
     * 둘레를 50m · 30°씩 넓혀 가며 처음 만난 점이라 가장 가까운 점과 수십 m 다를 수 있다
     */
    GeoPoint snap(Layer layer, GeoPoint point, double radiusMeters) {
        CellSet set = sets.get(layer);
        if (set == null || near(set, point)) {
            return point;
        }
        for (double r = SNAP_STEP_METERS; r <= radiusMeters; r += SNAP_STEP_METERS) {
            for (int bearing = 0; bearing < 360; bearing += SNAP_BEARING_STEP) {
                GeoPoint candidate = CandidateGenerator.destination(point, r, bearing);
                if (near(set, candidate)) {
                    return candidate;
                }
            }
        }
        return point;
    }

    private static boolean near(CellSet set, GeoPoint point) {
        double[] xy = SpotHeights.tm5179(point);
        return set.near(xy[0], xy[1]);
    }

    private static Map<Layer, CellSet> load(Path dir) {
        Map<Layer, CellSet> sets = new EnumMap<>(Layer.class);
        for (Layer layer : Layer.values()) {
            Path file = dir.resolve(layer.fileName());
            if (!Files.isRegularFile(file)) {
                log.warn("칸 집합 파일이 없어 {} 조건을 반영하지 않는다: {}", layer, file.toAbsolutePath());
                continue;
            }
            try (FileChannel channel = FileChannel.open(file, StandardOpenOption.READ)) {
                CellSet set = CellSet.read(channel.map(FileChannel.MapMode.READ_ONLY, 0, channel.size()));
                log.info("{} 칸 {}개를 읽었다", layer, set.keys().capacity());
                sets.put(layer, set);
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
        }
        return sets;
    }

    /** 표시된 칸의 키(오름차순). 키 = (행 << 20) | 열, 열 = floor(x / cell), 행 = floor(y / cell) */
    record CellSet(double cell, LongBuffer keys) {

        private static final String MAGIC = "WDCS";
        private static final int VERSION = 1;
        private static final int HEADER_BYTES = 20;

        /** build_layers.py가 쓴 파일(little-endian)을 읽는다 */
        static CellSet read(ByteBuffer file) {
            ByteBuffer b = file.order(ByteOrder.LITTLE_ENDIAN);
            byte[] magic = new byte[4];
            b.get(magic);
            if (!MAGIC.equals(new String(magic, StandardCharsets.US_ASCII)) || b.getInt() != VERSION) {
                throw new IllegalStateException("칸 집합 파일 형식이 다르다");
            }
            double cell = b.getDouble();
            int n = b.getInt();
            return new CellSet(cell, b.slice(HEADER_BYTES, n * Long.BYTES).order(ByteOrder.LITTLE_ENDIAN).asLongBuffer());
        }

        static CellSet of(double cell, long... sortedKeys) {
            return new CellSet(cell, LongBuffer.wrap(sortedKeys));
        }

        static long key(long col, long row) {
            return (row << 20) | col;
        }

        /** (x, y)가 든 칸이나 둘레 8칸이 표시돼 있다 */
        boolean near(double x, double y) {
            long col = (long) Math.floor(x / cell);
            long row = (long) Math.floor(y / cell);
            for (long r = row - 1; r <= row + 1; r++) {
                for (long c = col - 1; c <= col + 1; c++) {
                    if (contains(key(c, r))) {
                        return true;
                    }
                }
            }
            return false;
        }

        private boolean contains(long key) {
            int lo = 0;
            int hi = keys.capacity() - 1;
            while (lo <= hi) {
                int mid = (lo + hi) >>> 1;
                long v = keys.get(mid);
                if (v < key) {
                    lo = mid + 1;
                } else if (v > key) {
                    hi = mid - 1;
                } else {
                    return true;
                }
            }
            return false;
        }
    }
}

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
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.List;

/**
 * 후보 경로의 오르막(m). 국토지리정보원 표고점(약 540만 개) 격자 파일({@code app.course.planner.spot-heights})로 구한다.
 * 기준은 검증 스크립트 {@code slope_compare.py}와 같다. 시험 경로 60개에서 5m 등고선으로 구한 오르막과 상관 0.975였다.
 * <ol>
 *     <li>경로를 50m마다 다시 찍고, 점마다 반경 250m 안 표고점의 거리 제곱 역수 가중 평균(5m 안은 5m로 본다)으로 높이를 구한다</li>
 *     <li>높이를 모르는 점이 절반을 넘으면 오르막을 모른다(null). 나머지는 앞뒤 점으로 메운다</li>
 *     <li>이웃 3점 평균으로 다듬고(양 끝은 뺀다) 오른 높이를 모두 더한다</li>
 * </ol>
 * 파일은 {@code utilfile/_스크립트/course_planner/build_spot_heights.py}가 만든다(형식은 그 설명). 파일이 없으면 서버는 그대로 뜨고
 * 오르막을 모른다. 그때 평지 · 오르막 조건은 후보의 notApplied로 알린다.
 */
@Slf4j
@Component
class SpotHeights {

    static final double STEP_METERS = 50;
    static final double RADIUS_METERS = 250;
    static final double MIN_COVER = 0.5;
    private static final double MIN_WEIGHT_METERS = 5;

    /** null이면 파일이 없다 */
    private final Grid grid;

    /** 문자열로 받는다. Spring의 Path 변환은 "../utilfile/…"을 클래스패스 경로로 보고 거절한다 */
    @Autowired
    SpotHeights(@Value("${app.course.planner.spot-heights}") String file) {
        this(load(Path.of(file)));
    }

    SpotHeights(Grid grid) {
        this.grid = grid;
    }

    boolean available() {
        return grid != null;
    }

    /** 경로를 따라 오른 높이(m). 파일이 없거나 높이를 모르는 곳이 절반을 넘으면 null */
    Integer ascentMeters(List<GeoPoint> route) {
        if (grid == null) {
            return null;
        }
        List<double[]> samples = RouteMetrics.resample(route.stream().map(SpotHeights::tm5179).toList(), STEP_METERS);
        double[] z = new double[samples.size()];
        int known = 0;
        for (int i = 0; i < z.length; i++) {
            z[i] = grid.elevation(samples.get(i)[0], samples.get(i)[1]);
            if (!Double.isNaN(z[i])) {
                known++;
            }
        }
        if (z.length == 0 || known < MIN_COVER * z.length) {
            return z.length == 0 ? 0 : null;
        }
        fillGaps(z);
        double ascent = 0;
        for (int i = 2; i + 1 < z.length; i++) {
            ascent += Math.max(0, (z[i + 1] - z[i - 2]) / 3); // 이웃 3점 평균끼리의 차
        }
        return (int) Math.round(ascent);
    }

    /** 높이를 모르는 점을 앞뒤 아는 점 사이 직선으로 메운다. 양 끝은 가장 가까운 아는 값 */
    private static void fillGaps(double[] z) {
        int previous = -1;
        for (int i = 0; i <= z.length; i++) {
            if (i < z.length && Double.isNaN(z[i])) {
                continue;
            }
            for (int j = previous + 1; j < i; j++) {
                z[j] = previous < 0 ? z[i] : i == z.length ? z[previous] : z[previous] + (z[i] - z[previous]) * (j - previous) / (i - previous);
            }
            previous = i;
        }
    }

    private static Grid load(Path file) {
        if (!Files.isRegularFile(file)) {
            log.warn("표고점 파일이 없어 평지 · 오르막 조건을 반영하지 않는다: {}", file.toAbsolutePath());
            return null;
        }
        try (FileChannel channel = FileChannel.open(file, StandardOpenOption.READ)) {
            Grid grid = Grid.read(channel.map(FileChannel.MapMode.READ_ONLY, 0, channel.size()));
            log.info("표고점 {}개를 읽었다", grid.x().capacity());
            return grid;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    // EPSG:5179(Korea 2000 통합 좌표계) 횡메르카토르 정방향(Snyder). 검증 스크립트 tm5179.py와 같다
    private static final double A = 6_378_137.0;
    private static final double F = 1 / 298.257222101;
    private static final double E2 = F * (2 - F);
    private static final double EP2 = E2 / (1 - E2);
    private static final double K0 = 0.9996;
    private static final double LAT0 = Math.toRadians(38.0);
    private static final double LON0 = Math.toRadians(127.5);
    private static final double FALSE_EASTING = 1_000_000.0;
    private static final double FALSE_NORTHING = 2_000_000.0;
    private static final double M0 = meridian(LAT0);

    static double[] tm5179(GeoPoint p) {
        double phi = Math.toRadians(p.lat());
        double n = A / Math.sqrt(1 - E2 * Math.pow(Math.sin(phi), 2));
        double t = Math.pow(Math.tan(phi), 2);
        double c = EP2 * Math.pow(Math.cos(phi), 2);
        double a = (Math.toRadians(p.lng()) - LON0) * Math.cos(phi);
        double x = K0 * n * (a + (1 - t + c) * Math.pow(a, 3) / 6 + (5 - 18 * t + t * t + 72 * c - 58 * EP2) * Math.pow(a, 5) / 120);
        double y = K0 * (meridian(phi) - M0 + n * Math.tan(phi) * (a * a / 2 + (5 - t + 9 * c + 4 * c * c) * Math.pow(a, 4) / 24
                + (61 - 58 * t + t * t + 600 * c - 330 * EP2) * Math.pow(a, 6) / 720));
        return new double[]{x + FALSE_EASTING, y + FALSE_NORTHING};
    }

    private static double meridian(double phi) {
        double e4 = E2 * E2;
        double e6 = E2 * e4;
        return A * ((1 - E2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * phi
                - (3 * E2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * Math.sin(2 * phi)
                + (15 * e4 / 256 + 45 * e6 / 1024) * Math.sin(4 * phi)
                - (35 * e6 / 3072) * Math.sin(6 * phi));
    }

    /**
     * 표고점 격자(EPSG:5179 m). 칸 = 행 × cols + 열, 칸 안의 점은 x · y · z의 [start[칸], start[칸+1]).
     * 칸은 반경(250m)보다 커서 둘레 3×3칸만 본다.
     */
    record Grid(double x0, double y0, double cell, int cols, int rows, IntBuffer start, FloatBuffer x, FloatBuffer y, FloatBuffer z) {

        private static final String MAGIC = "WDSH";
        private static final int VERSION = 1;

        /** build_spot_heights.py가 쓴 파일(little-endian)을 읽는다 */
        static Grid read(ByteBuffer file) {
            ByteBuffer b = file.order(ByteOrder.LITTLE_ENDIAN);
            byte[] magic = new byte[4];
            b.get(magic);
            int version = b.getInt();
            if (!MAGIC.equals(new String(magic, StandardCharsets.US_ASCII)) || version != VERSION) {
                throw new IllegalStateException("표고점 파일 형식이 다르다");
            }
            double x0 = b.getDouble();
            double y0 = b.getDouble();
            double cell = b.getDouble();
            int cols = b.getInt();
            int rows = b.getInt();
            int n = b.getInt();
            int offset = b.position();
            IntBuffer start = slice(b, offset, (cols * rows + 1) * 4).asIntBuffer();
            offset += (cols * rows + 1) * 4;
            FloatBuffer x = slice(b, offset, n * 4).asFloatBuffer();
            FloatBuffer y = slice(b, offset + n * 4, n * 4).asFloatBuffer();
            FloatBuffer z = slice(b, offset + n * 8, n * 4).asFloatBuffer();
            return new Grid(x0, y0, cell, cols, rows, start, x, y, z);
        }

        private static ByteBuffer slice(ByteBuffer b, int offset, int length) {
            return b.slice(offset, length).order(ByteOrder.LITTLE_ENDIAN);
        }

        /** 반경 안 표고점이 없으면 NaN */
        double elevation(double px, double py) {
            int col = (int) Math.floor((px - x0) / cell);
            int row = (int) Math.floor((py - y0) / cell);
            double weights = 0;
            double sum = 0;
            for (int r = Math.max(row - 1, 0); r <= Math.min(row + 1, rows - 1); r++) {
                for (int c = Math.max(col - 1, 0); c <= Math.min(col + 1, cols - 1); c++) {
                    int k = r * cols + c;
                    for (int i = start.get(k); i < start.get(k + 1); i++) {
                        double d = Math.hypot(px - x.get(i), py - y.get(i));
                        if (d < RADIUS_METERS) {
                            double w = 1 / Math.pow(Math.max(d, MIN_WEIGHT_METERS), 2);
                            weights += w;
                            sum += w * z.get(i);
                        }
                    }
                }
            }
            return weights == 0 ? Double.NaN : sum / weights;
        }
    }
}

package com.wadadak.course.internal.course;

import com.wadadak.common.geo.GeoPoint;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.LineString;
import org.locationtech.jts.geom.PrecisionModel;

import java.util.List;

/** {@link GeoPoint} ↔ JTS 변환. JTS 좌표는 x = 경도, y = 위도다. */
public final class CourseGeometry {

    private static final GeometryFactory WGS84 = new GeometryFactory(new PrecisionModel(), 4326);

    private CourseGeometry() {
    }

    public static LineString lineString(List<GeoPoint> points) {
        return WGS84.createLineString(points.stream().map(p -> new Coordinate(p.lng(), p.lat())).toArray(Coordinate[]::new));
    }
}

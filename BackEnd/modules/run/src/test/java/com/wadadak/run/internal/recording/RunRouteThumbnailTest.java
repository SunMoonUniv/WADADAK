package com.wadadak.run.internal.recording;

import com.wadadak.common.geo.GeoPoint;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class RunRouteThumbnailTest {
    @Test void straightRouteIsReducedAndGapsKeepTheirOwnEndpoints() {
        var first=new ArrayList<GeoPoint>();
        var second=new ArrayList<GeoPoint>();
        for (int i=0;i<5000;i++) {
            first.add(new GeoPoint(36+i*.000001,127));
            second.add(new GeoPoint(36.02+i*.000001,127.01));
        }
        var original=List.of(List.copyOf(first),List.copyOf(second));
        var thumbnail=RunRouteThumbnail.create(original);
        assertThat(thumbnail.version()).isEqualTo("RUN_ROUTE_THUMBNAIL_V1");
        assertThat(thumbnail.segments()).containsExactly(
                List.of(first.getFirst(),first.getLast()),List.of(second.getFirst(),second.getLast()));
        assertThat(original.getFirst()).hasSize(5000);
        assertThat(original.getLast()).hasSize(5000);
    }

    @Test void cornersAndClosedLoopSurviveSimplification() {
        var a=new GeoPoint(36,127);
        var b=new GeoPoint(36.001,127);
        var c=new GeoPoint(36.001,127.001);
        var d=new GeoPoint(36,127.001);
        var loop=List.of(a,new GeoPoint(36.0005,127),b,c,d,a);
        assertThat(RunRouteThumbnail.create(List.of(loop)).segments()).containsExactly(List.of(a,b,c,d,a));
    }

    @Test void pointBudgetIsSharedAcrossSegmentsWithoutDroppingEndpointsOrReordering() {
        var segments=new ArrayList<List<GeoPoint>>();
        for (int segment=0;segment<4;segment++) {
            var points=new ArrayList<GeoPoint>();
            for (int i=0;i<1000;i++) points.add(new GeoPoint(36+segment*.03+(i%2)*.001,127+i*.00001));
            segments.add(List.copyOf(points));
        }
        var thumbnail=RunRouteThumbnail.create(segments);
        assertThat(thumbnail.segments()).hasSize(4);
        assertThat(thumbnail.segments().stream().mapToInt(List::size).sum()).isEqualTo(128);
        for (int i=0;i<segments.size();i++) {
            var source=segments.get(i);
            var reduced=thumbnail.segments().get(i);
            assertThat(reduced.getFirst()).isEqualTo(source.getFirst());
            assertThat(reduced.getLast()).isEqualTo(source.getLast());
            assertThat(source).containsSubsequence(reduced);
        }
        assertThat(RunRouteThumbnail.create(segments)).isEqualTo(thumbnail);
    }

    @Test void emptySingletonAndRepeatedPointsAreSafe() {
        var point=new GeoPoint(36,127);
        assertThat(RunRouteThumbnail.create(null).segments()).isEmpty();
        assertThat(RunRouteThumbnail.create(List.of()).segments()).isEmpty();
        assertThat(RunRouteThumbnail.create(List.of(List.of(),List.of(point),List.of(point,point,point))).segments())
                .containsExactly(List.of(point),List.of(point,point));
    }

    @Test void extremeFragmentationReturnsEmptyRatherThanJoiningOrDroppingFragments() {
        var segment=List.of(new GeoPoint(36,127),new GeoPoint(36.001,127));
        var fragments=new ArrayList<List<GeoPoint>>();
        for (int i=0;i<64;i++) fragments.add(segment);
        assertThat(RunRouteThumbnail.create(fragments).segments()).hasSize(64);
        fragments.add(segment);
        assertThat(RunRouteThumbnail.create(fragments).segments()).isEmpty();
    }
}

package com.wadadak.run.internal.recording;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.RunContracts.RouteThumbnail;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.PriorityQueue;
import java.util.TreeSet;

/** 기록 처리에서 이미 계산한 정제 경로만 사용한다. DB·원본 입력을 읽지 않는다. */
final class RunRouteThumbnail {
    static final String VERSION = "RUN_ROUTE_THUMBNAIL_V1";
    static final int MAX_POINTS = 128;
    private static final double TOLERANCE_METERS = 8;

    private RunRouteThumbnail() {}

    static RouteThumbnail create(List<List<GeoPoint>> segments) {
        if (segments == null || segments.isEmpty()) return empty();
        // 구간 끝점을 버리거나 공백을 잇지 않는다. 너무 잘게 끊긴 경로는 썸네일을 비운다.
        long minimum = segments.stream().mapToLong(s -> Math.min(2,s.size())).sum();
        if (minimum > MAX_POINTS) return empty();

        var kept = new ArrayList<TreeSet<Integer>>();
        var candidates = new PriorityQueue<Candidate>(Comparator
                .comparingDouble(Candidate::errorSquared).reversed()
                .thenComparingInt(Candidate::segment).thenComparingInt(Candidate::from));
        int count = (int) minimum;
        for (int i=0;i<segments.size();i++) {
            List<GeoPoint> points=segments.get(i);
            var indices=new TreeSet<Integer>();
            if (!points.isEmpty()) { indices.add(0); indices.add(points.size()-1); }
            kept.add(indices);
            if (count < MAX_POINTS) addCandidate(candidates,segments,i,0,points.size()-1);
        }
        // Douglas-Peucker의 가장 큰 굴곡부터 남긴다. 모든 구간이 같은 점 수 예산을 공유한다.
        while (count < MAX_POINTS && !candidates.isEmpty()) {
            Candidate next=candidates.remove();
            kept.get(next.segment()).add(next.split());
            count++;
            if (count < MAX_POINTS) {
                addCandidate(candidates,segments,next.segment(),next.from(),next.split());
                addCandidate(candidates,segments,next.segment(),next.split(),next.to());
            }
        }
        var reduced=new ArrayList<List<GeoPoint>>();
        for (int i=0;i<segments.size();i++) {
            List<GeoPoint> points=segments.get(i);
            if (!points.isEmpty()) reduced.add(kept.get(i).stream().map(points::get).toList());
        }
        return new RouteThumbnail(VERSION,List.copyOf(reduced));
    }

    private static RouteThumbnail empty() { return new RouteThumbnail(VERSION,List.of()); }

    private record Candidate(int segment, int from, int to, int split, double errorSquared) {}

    private static void addCandidate(PriorityQueue<Candidate> candidates, List<List<GeoPoint>> segments,
                                     int segment, int from, int to) {
        if (to-from < 2) return;
        List<GeoPoint> points=segments.get(segment);
        GeoPoint start=points.get(from), end=points.get(to);
        double longitudeScale=Math.cos(Math.toRadians((start.lat()+end.lat())/2));
        double x=meters(end.lng()-start.lng())*longitudeScale, y=meters(end.lat()-start.lat());
        double lengthSquared=x*x+y*y;
        double largest=TOLERANCE_METERS*TOLERANCE_METERS;
        int split=-1;
        for (int i=from+1;i<to;i++) {
            GeoPoint point=points.get(i);
            double px=meters(point.lng()-start.lng())*longitudeScale, py=meters(point.lat()-start.lat());
            double t=lengthSquared==0?0:Math.clamp((px*x+py*y)/lengthSquared,0,1);
            double dx=px-t*x, dy=py-t*y, error=dx*dx+dy*dy;
            if (error > largest) { largest=error; split=i; }
        }
        if (split>=0) candidates.add(new Candidate(segment,from,to,split,largest));
    }

    private static double meters(double degrees) { return Math.toRadians(degrees)*GeoPoint.EARTH_RADIUS_M; }
}

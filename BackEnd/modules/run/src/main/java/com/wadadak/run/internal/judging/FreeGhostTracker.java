package com.wadadak.run.internal.judging;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.GpsQuality;
import com.wadadak.run.internal.RunContracts.Input;
import com.wadadak.run.internal.RunContracts.Kind;
import com.wadadak.run.internal.judging.CourseTracker.Point;
import com.wadadak.run.internal.judging.RouteGeometry.Projection;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Opt-in FREE_V2 matcher. Shared verbatim in behaviour with the incremental Dart matcher.
 * Scores spatial fit, plausible movement and heading; competing route branches wait for evidence.
 * Hard GPS boundaries and completion/distance policy remain in GpsQuality/CourseJudge. */
final class FreeGhostTracker {
    private static final int MAX_BRANCHES = 8;
    private static final double BRANCH_SEPARATION_M = 20;
    private static final double CONFIDENCE_MARGIN = 9;
    private static final double EPS = 1e-6;
    private final RouteGeometry route;
    private final JudgingConfig config;
    private final List<Point> points = new ArrayList<>();
    private List<State> states = List.of();
    private Input previous;
    private boolean confirmed;

    private record Node(int index, double s, boolean connected, Node previous) {}
    private record State(double s, double max, double cost, Node path) {}
    FreeGhostTracker(RouteGeometry route, JudgingConfig config) {this.route=route;this.config=config;}

    List<Point> track(List<Input> inputs) {
        boolean paused=false;
        for(var input:inputs) {
            if(input.kind()==Kind.END || input.kind()==Kind.SEGMENT_END)break;
            switch(input.kind()) {
                case GPS -> {if(!paused)sample(input);}
                case PAUSE -> {paused=true;reset();}
                case RESUME -> {paused=false;reset();}
                case GAP -> reset();
                default -> {}
            }
        }
        return points; // Unresolved branches remain unknown; no end-of-record guesses.
    }
    private void reset() {states=List.of();previous=null;confirmed=false;}
    private void sample(Input input) {
        int index=points.size();
        points.add(new Point(input.seq(),input.elapsedMs(),input.measuredAt(),null,false));
        if(!GpsQuality.good(input)){reset();return;}
        var prior=previous;
        long dt=prior==null?0:input.elapsedMs()-prior.elapsedMs();
        double moved=prior==null?0:prior.location().distanceMeters(input.location());
        if(prior!=null && (dt<=0 || dt>GpsQuality.MAX_INTERVAL_MS)) {
            reset();prior=null;
        } else if(prior!=null && moved*1000/dt>config.maxSpeedMps()) {
            reset();previous=input;return; // The jump fix itself is not a trustworthy position.
        }
        var candidates=route.candidates(route.toLocal(input.location()),config.routeToleranceM());
        if(candidates.isEmpty()){reset();return;}
        var expanded=new ArrayList<State>();
        if(!states.isEmpty() && prior!=null) {
            double reach=dt/1000.0*config.maxSpeedMps()+config.routeToleranceM();
            for(var state:states)for(var candidate:candidates) {
                double delta=candidate.s()-state.s();
                if(Math.abs(delta)>reach+EPS || (!confirmed && candidate.s()<state.max()-config.routeToleranceM()-EPS))continue;
                double error=Math.abs(delta)-moved;
                double heading=route.directionCosine(prior.location(),input.location(),candidate.segment());
                if(delta<0)heading=-heading;
                double cost=state.cost()+candidate.d()*candidate.d()+.25*error*error
                        +(delta<0?.25*moved*moved:0)
                        +(moved<.25 || Math.abs(delta)<.25?0:.5*moved*moved*(1-heading));
                expanded.add(new State(candidate.s(),Math.max(state.max(),candidate.s()),cost,
                        new Node(index,candidate.s(),true,state.path())));
            }
        }
        if(expanded.isEmpty()) {
            // Reacquire without connecting the unobserved/jumped interval.
            states=List.of();confirmed=false;
            for(var candidate:candidates)expanded.add(new State(candidate.s(),candidate.s(),candidate.d()*candidate.d(),
                    new Node(index,candidate.s(),false,null)));
        }
        expanded.sort(Comparator.comparingDouble(State::cost).thenComparingDouble(State::s));
        var branches=new ArrayList<State>();
        for(var state:expanded) {
            if(branches.stream().noneMatch(b->Math.abs(b.s()-state.s())<=BRANCH_SEPARATION_M+EPS))branches.add(state);
            if(branches.size()>MAX_BRANCHES) {
                // Truncating equally plausible paths could manufacture certainty. Wait and reacquire instead.
                reset();previous=input;return;
            }
        }
        var best=branches.getFirst();
        boolean clear=branches.size()==1 || branches.get(1).cost()-best.cost()>CONFIDENCE_MARGIN;
        previous=input;
        if(clear) {
            for(var node=best.path();node!=null;node=node.previous()) {
                var original=points.get(node.index());
                points.set(node.index(),new Point(original.seq(),original.elapsedMs(),original.measuredAt(),node.s(),node.connected()));
            }
            states=List.of(new State(best.s(),best.max(),0,null));confirmed=true;
        } else {
            states=branches.stream().map(s->new State(s.s(),s.max(),s.cost()-best.cost(),s.path())).toList();
        }
    }
}

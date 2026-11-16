package com.wadadak.run.internal;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.RunContracts.Input;
import com.wadadak.run.internal.RunContracts.Kind;
import java.util.ArrayList;
import java.util.List;

/** PACE_V4 derived coordinates only; raw inputs, timestamps and sequence numbers are immutable. */
public final class GpsPathFilter {
    private boolean enabled;
    private Input before, pending, stationary;
    private final List<Input> deferred = new ArrayList<>();

    public static List<Input> normalize(List<Input> inputs) {
        if (inputs.isEmpty() || !"PACE_V4".equals(inputs.getFirst().reason())) return inputs;
        var filter = new GpsPathFilter();
        var result = new ArrayList<Input>();
        for (var input : inputs) result.addAll(filter.add(input));
        // A live prefix intentionally retains one GPS fix until the next fix or boundary.
        return List.copyOf(result);
    }

    public List<Input> add(Input p) {
        if (p.kind() == Kind.START) enabled = "PACE_V4".equals(p.reason());
        if (!enabled) return List.of(p);
        var out = new ArrayList<Input>();
        if (p.kind() == Kind.CADENCE || p.kind() == Kind.BAROMETER || p.kind() == Kind.SEGMENT_END) {
            if (pending != null && p.elapsedMs() - pending.elapsedMs() <= 10_000) {
                deferred.add(p);
                return out;
            }
            if (before != null && p.elapsedMs() - before.elapsedMs() > 10_000) {
                flush(out, false);
                reset();
            }
            out.add(p);
            return out;
        }
        if (p.kind() != Kind.GPS) {
            flush(out, true);
            reset();
            out.add(p);
            return out;
        }
        Input last = pending != null ? pending : before;
        // Never hide a hard RAW boundary with a softened endpoint.
        if (!usable(p) || (last != null && !connected(last, p))) {
            flush(out, false);
            reset();
            out.add(p);
            if (usable(p)) before = p;
            return out;
        }
        // Without speed evidence no correction is permitted, so do not delay live metrics.
        if (!reliable(p) || (last != null && !reliable(last))) {
            flush(out, false);
            reset();
            out.add(p);
            before=p;
            return out;
        }
        if (before == null) {
            before = p;
            out.add(p); // Preserve the start endpoint exactly.
            return out;
        }
        if (pending == null) {
            pending = p;
            return out;
        }
        updateStationary(before, pending, p);
        out.add(clean(before, pending, p));
        out.addAll(deferred);
        deferred.clear();
        before = pending;
        pending = p;
        return out;
    }

    private void updateStationary(Input a, Input b, Input c) {
        if (stationary != null && (!stopped(c) || distance(stationary,c) > radius(stationary))) stationary = null;
        if (stationary == null && stopped(a) && stopped(b) && stopped(c)
                && c.elapsedMs()-a.elapsedMs() >= 2000
                && distance(a,b) <= radius(a) && distance(a,c) <= radius(a)) stationary = a;
    }

    private Input clean(Input a, Input b, Input c) {
        if (stationary != null && stopped(b) && distance(stationary,b) <= radius(stationary))
            return at(b,stationary.location());
        if (!reliable(a) || !reliable(b) || !reliable(c)) return b;
        long dt = c.elapsedMs()-a.elapsedMs();
        if (dt <= 0 || dt > 6000) return b;
        double t = (double)(b.elapsedMs()-a.elapsedMs())/dt;
        GeoPoint interpolation = new GeoPoint(a.location().lat()+(c.location().lat()-a.location().lat())*t,
                a.location().lng()+(c.location().lng()-a.location().lng())*t);
        double deviation = b.location().distanceMeters(interpolation);
        double ab=distance(a,b), bc=distance(b,c), ac=distance(a,c);
        double expected=(a.speedMps()+2*b.speedMps()+c.speedMps())*.25*dt/1000;
        // Only a small detour contradicted by accurate speed can be removed; real hairpins survive.
        if (deviation <= 6 && deviation > 1 && ab+bc > ac*1.5
                && ab+bc > expected+4 && ac <= expected+2) return at(b,interpolation);
        // Gentle, moving jitter only. Preserve sharp corners, slow walking and endpoints.
        double cosine = ab*bc == 0 ? -1 : (ac*ac-ab*ab-bc*bc)/(2*ab*bc);
        if (a.speedMps() >= .3 && b.speedMps() >= .3 && c.speedMps() >= .3
                && cosine >= .5 && deviation <= 2 && deviation >= .05) {
            double weight=Math.min(.5,1/deviation);
            return at(b,new GeoPoint(b.location().lat()+(interpolation.lat()-b.location().lat())*weight,
                    b.location().lng()+(interpolation.lng()-b.location().lng())*weight));
        }
        return b;
    }

    private void flush(List<Input> out, boolean holdStop) {
        if (pending != null) out.add(holdStop && stationary != null && stopped(pending)
                && distance(stationary,pending) <= radius(stationary) ? at(pending,stationary.location()) : pending);
        out.addAll(deferred);
        deferred.clear();
        pending=null;
    }
    private void reset() { before=null; pending=null; stationary=null; }
    private static double radius(Input p) { return Math.max(3,Math.min(6,p.accuracyM())); }
    private static double distance(Input a,Input b) { return a.location().distanceMeters(b.location()); }
    private static boolean usable(Input p) { return GpsQuality.good(p) && p.accuracyM() <= 15; }
    private static boolean connected(Input a,Input b) {
        long dt=b.elapsedMs()-a.elapsedMs();
        return usable(a) && dt>0 && dt<=10_000 && distance(a,b)*1000/dt<=12;
    }
    private static boolean reliable(Input p) {
        return usable(p) && p.speedMps()!=null && Double.isFinite(p.speedMps()) && p.speedMps()>=0 && p.speedMps()<=12
                && p.speedAccuracyMps()!=null && Double.isFinite(p.speedAccuracyMps())
                && p.speedAccuracyMps()>0 && p.speedAccuracyMps()<=.5;
    }
    private static boolean stopped(Input p) { return reliable(p) && p.speedMps()<=.2; }
    private static Input at(Input p,GeoPoint location) {
        return new Input(p.seq(),p.kind(),p.elapsedMs(),p.measuredAt(),location,p.accuracyM(),p.reason(),
                p.speedMps(),p.speedAccuracyMps(),p.steps(),p.durationMs(),p.sampleEndMs(),
                p.altitudeM(),p.altitudeAccuracyM(),p.pressureHpa(),p.pressureAccuracy());
    }
}

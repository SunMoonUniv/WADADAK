package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.CourseApi;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.*;
import java.time.temporal.TemporalAdjusters;
import java.util.*;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

/** F9 projection over existing records. Never loads GPS inputs or builds replay for a page. */
@Service
class OwnGhostCandidates {
    private final NamedParameterJdbcTemplate db;
    private final RunLocks locks;
    private final WithdrawnRunMemberRepository withdrawals;
    private final Clock clock;
    private final CourseApi courses;
    private final JsonMapper json;
    private final TransactionTemplate readOnly;
    OwnGhostCandidates(NamedParameterJdbcTemplate db, RunLocks locks, WithdrawnRunMemberRepository withdrawals, Clock clock,
                       CourseApi courses, JsonMapper json, PlatformTransactionManager transactionManager) {
        this.readOnly = new TransactionTemplate(transactionManager);
        this.readOnly.setReadOnly(true);
        this.db = db; this.locks = locks; this.withdrawals = withdrawals; this.clock = clock;
        this.courses=courses; this.json=json;
    }

    private record SelectionRows(List<OwnGhostCandidate> rows, OwnGhostSummary summary) {}

    private record Position(long seconds, Instant startedAt, UUID id) {}
    private static Position position(String cursor, String scope) {
        if (cursor == null) return null;
        try {
            String[] p = cursor.split("\\|", -1);
            if (cursor.length() > 512 || p.length != 8
                    || !String.join("|", Arrays.copyOf(p, 5)).equals(scope)) throw new IllegalArgumentException();
            long seconds = Long.parseLong(p[5]);
            Instant startedAt = Instant.parse(p[6]);
            if (seconds < 0 || startedAt.isBefore(Instant.parse("0001-01-01T00:00:00Z"))
                    || startedAt.isAfter(Instant.parse("9999-12-31T23:59:59Z"))) throw new IllegalArgumentException();
            return new Position(seconds, startedAt, UUID.fromString(p[7]));
        } catch (RuntimeException e) { throw new AppException(RunErrorCode.INVALID); }
    }
    private static OwnGhostCandidate candidate(ResultSet rs, UUID courseId, long version, String prefix) throws SQLException {
        Timestamp completed = rs.getTimestamp(prefix + "completed_at");
        return new OwnGhostCandidate(rs.getObject(prefix + "id", UUID.class), courseId, version,
            rs.getTimestamp(prefix + "started_at").toInstant(), completed == null ? null : completed.toInstant(),
            rs.getTimestamp(prefix + "registered_at").toInstant(), rs.getLong(prefix + "seconds"), rs.getInt(prefix + "distance"),
            rs.getObject(prefix + "cadence", Double.class));
    }

    /** Course read happens before the read-only transaction: no DB connection or member lock is held while waiting on it. */
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public OwnGhostCandidatePage list(UUID owner, UUID courseId, long version, OwnGhostSort sort,
            OwnGhostPeriod period, Cursorable page) {
        if (version < 0 || sort == null || period == null || page.size() < 1 || page.size() > Cursorable.MAX_SIZE)
            throw new AppException(RunErrorCode.INVALID);
        // Read-only preparation: no run/course start, source rewrite, GPS scan or event publication.
        var current = courses.getRouteForRun(courseId);
        if (!courseId.equals(current.courseId()) || current.version()!=version)
            throw new AppException(RunErrorCode.CONFLICT);
        LocalDate today = LocalDate.now(clock.withZone(ZoneId.of("Asia/Seoul")));
        LocalDate first = switch (period) {
            case ALL -> null;
            case MONTH -> today.withDayOfMonth(1);
            case WEEK -> today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        };
        Instant from = first == null ? null : first.atStartOfDay(ZoneId.of("Asia/Seoul")).toInstant();
        String scope = courseId + "|" + version + "|" + sort + "|" + period + "|" + (from == null ? "-" : from);
        Position after = position(page.cursor(), scope);
        Map<String, Object> args = new HashMap<>();
        args.put("owner", owner); args.put("courseId", courseId.toString()); args.put("version", Long.toString(version));
        args.put("courseUuid", courseId); args.put("numericVersion", version);
        args.put("distance", current.totalDistanceMeters()); args.put("route", json.writeValueAsString(current.route()));
        args.put("limit", page.size() + 1);
        String periodWhere = "";
        if (from != null) {
            LocalDate end = period == OwnGhostPeriod.MONTH ? first.plusMonths(1) : first.plusWeeks(1);
            args.put("from", Timestamp.from(from));
            args.put("until", Timestamp.from(end.atStartOfDay(ZoneId.of("Asia/Seoul")).toInstant()));
            periodWhere = " AND s.started_at >= :from AND s.started_at < :until";
        }
        String base = """
            WITH candidates AS MATERIALIZED (
                SELECT r.id, s.started_at, r.registered_at,
                       (r.result_json::jsonb #>> '{course,completedAt}')::timestamptz completed_at,
                       (r.result_json::jsonb #>> '{course,courseElapsedSeconds}')::bigint seconds,
                       (r.result_json::jsonb #>> '{course,courseDistanceMeters}')::integer distance,
                       (r.result_json::jsonb #>> '{metrics,averageCadence}')::double precision cadence
                FROM run.records r JOIN run.sessions s ON s.id = r.id
                LEFT JOIN run.course_attempts c ON c.session_id=r.id AND c.member_id=s.member_id
                WHERE s.member_id = :owner AND s.processing = 'DONE'
                  AND r.result_json::jsonb #>> '{course,completed}' = 'true'
                  AND r.result_json::jsonb #>> '{course,courseId}' = :courseId
                  AND (r.result_json::jsonb #>> '{course,courseVersion}' = :version
                    OR ((r.result_json::jsonb #>> '{course,courseVersion}')::bigint < :numericVersion
                      AND c.course_id=:courseUuid
                      AND c.course_version=(r.result_json::jsonb #>> '{course,courseVersion}')::bigint
                      AND c.total_distance_meters=:distance
                      AND (r.result_json::jsonb #>> '{course,courseDistanceMeters}')::integer=:distance
                      AND c.route_json::jsonb=CAST(:route AS jsonb)))
                  AND NOT EXISTS (SELECT 1 FROM run.deleted_records d WHERE d.id = r.id)
            """ + periodWhere + """
                UNION ALL
                SELECT l.source_record_id id,s.started_at,r.registered_at,l.completed_at,
                       l.course_elapsed_seconds seconds,
                       (l.performance_json::jsonb ->> 'courseDistanceMeters')::integer distance,
                       (r.result_json::jsonb #>> '{metrics,averageCadence}')::double precision cadence
                FROM run.gps_source_links l JOIN run.sessions s ON s.id=l.source_record_id
                JOIN run.records r ON r.id=l.source_record_id
                WHERE l.member_id=:owner AND s.processing='DONE' AND l.status='LINKED'
                  AND l.course_id=:courseUuid
                  AND (l.snapshot_json::jsonb ->> 'courseVersion')::bigint<=:numericVersion
                  AND (l.snapshot_json::jsonb ->> 'distanceMeters')::integer=:distance
                  AND l.snapshot_json::jsonb -> 'route'=CAST(:route AS jsonb)
                  AND NOT EXISTS(SELECT 1 FROM run.deleted_records d WHERE d.id=l.source_record_id)
            """ + periodWhere + ") ";
        String boundary = "";
        if (after != null) {
            args.put("afterSeconds", after.seconds());
            args.put("afterStart", Timestamp.from(after.startedAt()));
            args.put("afterId", after.id());
            boundary = sort == OwnGhostSort.RECENT
                ? "WHERE (started_at, id) < (:afterStart, :afterId)"
                : "WHERE seconds > :afterSeconds OR (seconds = :afterSeconds AND (started_at, id) < (:afterStart, :afterId))";
        }
        String order = sort == OwnGhostSort.BEST ? "seconds ASC, started_at DESC, id DESC" : "started_at DESC, id DESC";
        // One materialized candidate set supplies both the whole-list summary and this page.
        String query = base + """
                , summary AS (SELECT count(*) total_count, avg(seconds) average_seconds FROM candidates),
                best AS (SELECT * FROM candidates ORDER BY seconds ASC, started_at DESC, id DESC LIMIT 1),
                page AS (SELECT * FROM candidates
                """ + boundary + " ORDER BY " + order + " LIMIT :limit) " + """
                SELECT summary.total_count, summary.average_seconds,
                    best.id best_id, best.started_at best_started_at, best.registered_at best_registered_at,
                    best.completed_at best_completed_at, best.seconds best_seconds,
                    best.distance best_distance, best.cadence best_cadence,
                    page.id page_id, page.started_at page_started_at, page.registered_at page_registered_at,
                    page.completed_at page_completed_at, page.seconds page_seconds,
                    page.distance page_distance, page.cadence page_cadence
                FROM summary LEFT JOIN best ON true LEFT JOIN page ON true
                ORDER BY
                """ + (sort == OwnGhostSort.BEST
                        ? "page.seconds ASC, page.started_at DESC, page.id DESC"
                        : "page.started_at DESC, page.id DESC");
        var selection = readOnly.execute(status -> {
            locks.member(owner);
            if (withdrawals.existsById(owner)) throw new AppException(RunErrorCode.NOT_FOUND);
            return db.query(query, args, rs -> {
                OwnGhostSummary summary = new OwnGhostSummary(0, null, null);
                List<OwnGhostCandidate> rows = new ArrayList<>();
                boolean summaryRead = false;
                while (rs.next()) {
                    if (!summaryRead) {
                        double average = rs.getDouble("average_seconds");
                        Double averageSeconds = rs.wasNull() ? null : average;
                        summary = new OwnGhostSummary(rs.getLong("total_count"),
                                averageSeconds,
                                rs.getObject("best_id") == null ? null : candidate(rs, courseId, version, "best_"));
                        summaryRead = true;
                    }
                    if (rs.getObject("page_id") != null) rows.add(candidate(rs, courseId, version, "page_"));
                }
                return new SelectionRows(rows, summary);
            });
        });
        var rows = selection.rows();
        boolean more = rows.size() > page.size();
        var content = List.copyOf(rows.subList(0, Math.min(page.size(), rows.size())));
        OwnGhostCandidate last = content.isEmpty() ? null : content.getLast();
        String next = more ? scope + "|" + last.courseElapsedSeconds() + "|" + last.startedAt() + "|" + last.id() : null;
        return new OwnGhostCandidatePage(content, next, selection.summary());
    }
}

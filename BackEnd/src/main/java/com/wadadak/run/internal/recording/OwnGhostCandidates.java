package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.paging.Cursorable;
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
import org.springframework.transaction.annotation.Transactional;

/** F9 projection over existing records. Never loads GPS inputs or builds replay for a page. */
@Service
class OwnGhostCandidates {
    private final NamedParameterJdbcTemplate db;
    private final RunLocks locks;
    private final WithdrawnRunMemberRepository withdrawals;
    private final Clock clock;
    OwnGhostCandidates(NamedParameterJdbcTemplate db, RunLocks locks, WithdrawnRunMemberRepository withdrawals, Clock clock) {
        this.db = db; this.locks = locks; this.withdrawals = withdrawals; this.clock = clock;
    }

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
    private static OwnGhostCandidate candidate(ResultSet rs, UUID courseId, long version) throws SQLException {
        Timestamp completed = rs.getTimestamp("completed_at");
        return new OwnGhostCandidate(rs.getObject("id", UUID.class), courseId, version,
            rs.getTimestamp("started_at").toInstant(), completed == null ? null : completed.toInstant(),
            rs.getTimestamp("registered_at").toInstant(), rs.getLong("seconds"), rs.getInt("distance"),
            rs.getObject("cadence", Double.class));
    }

    @Transactional(readOnly = true)
    public OwnGhostCandidatePage list(UUID owner, UUID courseId, long version, OwnGhostSort sort,
            OwnGhostPeriod period, Cursorable page) {
        if (version < 0 || sort == null || period == null || page.size() < 1 || page.size() > Cursorable.MAX_SIZE)
            throw new AppException(RunErrorCode.INVALID);
        LocalDate today = LocalDate.now(clock.withZone(ZoneId.of("Asia/Seoul")));
        LocalDate first = switch (period) {
            case ALL -> null;
            case MONTH -> today.withDayOfMonth(1);
            case WEEK -> today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        };
        Instant from = first == null ? null : first.atStartOfDay(ZoneId.of("Asia/Seoul")).toInstant();
        String scope = courseId + "|" + version + "|" + sort + "|" + period + "|" + (from == null ? "-" : from);
        Position after = position(page.cursor(), scope);
        locks.member(owner);
        if (withdrawals.existsById(owner)) throw new AppException(RunErrorCode.NOT_FOUND);
        Map<String, Object> args = new HashMap<>();
        args.put("owner", owner); args.put("courseId", courseId.toString()); args.put("version", Long.toString(version));
        args.put("limit", page.size() + 1);
        String periodWhere = "";
        if (from != null) {
            LocalDate end = period == OwnGhostPeriod.MONTH ? first.plusMonths(1) : first.plusWeeks(1);
            args.put("from", Timestamp.from(from));
            args.put("until", Timestamp.from(end.atStartOfDay(ZoneId.of("Asia/Seoul")).toInstant()));
            periodWhere = " AND s.started_at >= :from AND s.started_at < :until";
        }
        String base = """
            WITH candidates AS (
                SELECT r.id, s.started_at, r.registered_at,
                       (r.result_json::jsonb #>> '{course,completedAt}')::timestamptz completed_at,
                       (r.result_json::jsonb #>> '{course,courseElapsedSeconds}')::bigint seconds,
                       (r.result_json::jsonb #>> '{course,courseDistanceMeters}')::integer distance,
                       (r.result_json::jsonb #>> '{metrics,averageCadence}')::double precision cadence
                FROM run.records r JOIN run.sessions s ON s.id = r.id
                WHERE s.member_id = :owner AND s.processing = 'DONE'
                  AND r.result_json::jsonb #>> '{course,completed}' = 'true'
                  AND r.result_json::jsonb #>> '{course,courseId}' = :courseId
                  AND r.result_json::jsonb #>> '{course,courseVersion}' = :version
                  AND NOT EXISTS (SELECT 1 FROM run.deleted_records d WHERE d.id = r.id)
            """ + periodWhere + ") ";
        // Summary includes every matching completion, not only the currently loaded page.
        var summaries = db.query(base + """
            SELECT *, count(*) OVER() total_count, avg(seconds) OVER() average_seconds
            FROM candidates ORDER BY seconds ASC, started_at DESC, id DESC LIMIT 1
            """, args, (rs, n) -> new OwnGhostSummary(rs.getLong("total_count"),
                rs.getDouble("average_seconds"), candidate(rs, courseId, version)));
        OwnGhostSummary summary = summaries.isEmpty() ? new OwnGhostSummary(0, null, null) : summaries.getFirst();
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
        var rows = db.query(base + "SELECT * FROM candidates " + boundary + " ORDER BY " + order + " LIMIT :limit", args,
            (rs, n) -> candidate(rs, courseId, version));
        boolean more = rows.size() > page.size();
        var content = List.copyOf(rows.subList(0, Math.min(page.size(), rows.size())));
        OwnGhostCandidate last = content.isEmpty() ? null : content.getLast();
        String next = more ? scope + "|" + last.courseElapsedSeconds() + "|" + last.startedAt() + "|" + last.id() : null;
        return new OwnGhostCandidatePage(content, next, summary);
    }
}

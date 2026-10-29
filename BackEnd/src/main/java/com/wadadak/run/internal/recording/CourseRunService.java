package com.wadadak.run.internal.recording;

import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.event.run.CourseActiveRunnersChangedEvent;
import com.wadadak.event.run.CourseRunStartedEvent;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.CourseOutcome;
import com.wadadak.run.internal.RunContracts.CourseSnapshot;
import com.wadadak.run.internal.RunContracts.Input;
import com.wadadak.run.internal.judging.CourseJudge;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * 코스 러닝 세션(F6 B단계). 정책 D-08: 코스 러닝은 시작할 때 서버 연결이 필요하고, 시작 뒤에는 통신 없이 달린다.
 * <ol>
 *   <li>준비(C6): 코스 활성 여부를 확인하고 판정용 경로 스냅샷을 저장한다</li>
 *   <li>시작 신호(카운트다운 끝): 도전 수 이벤트와 현재 러너 수 +1</li>
 *   <li>현재 러너 수 −1: 구간 종료 신호 → 기록 업로드 → 시작 후 {@link #ACTIVE_TIMEOUT} 중 먼저 오는 것(공통 7·D-14)</li>
 *   <li>업로드 처리: 저장한 스냅샷으로 판정해 결과에 붙인다({@link RunService#process})</li>
 * </ol>
 * 자유 러닝 세션의 구간 종료 신호나 이미 끝난 시도는 거부하지 않고 무시한다(재시도도 같은 결과).
 */
@Service
class CourseRunService {

    /** ponytail: 정책 D-14 남은 결정(예: 3시간). 값이 정해지면 설정으로 옮긴다 */
    static final Duration ACTIVE_TIMEOUT = Duration.ofHours(3);

    private final CourseAttemptRepository attempts;
    private final CourseRunnerCounts counts;
    private final RunSessionRepository sessions;
    private final DeletedRunRecordRepository deletedRecords;
    private final WithdrawnRunMemberRepository withdrawnMembers;
    private final RunLocks locks;
    private final CourseApi courseApi;
    private final JsonMapper json;
    private final ApplicationEventPublisher events;
    private final Clock clock;
    private final CourseJudge judge = new CourseJudge();

    CourseRunService(CourseAttemptRepository attempts, CourseRunnerCounts counts, RunSessionRepository sessions,
                     DeletedRunRecordRepository deletedRecords, WithdrawnRunMemberRepository withdrawnMembers,
                     RunLocks locks, CourseApi courseApi, JsonMapper json, ApplicationEventPublisher events, Clock clock) {
        this.attempts = attempts;
        this.counts = counts;
        this.sessions = sessions;
        this.deletedRecords = deletedRecords;
        this.withdrawnMembers = withdrawnMembers;
        this.locks = locks;
        this.courseApi = courseApi;
        this.json = json;
        this.events = events;
        this.clock = clock;
    }

    /** 준비. 같은 세션·같은 코스 재시도는 처음 저장한 스냅샷을 그대로 돌려준다 */
    @Transactional
    public CourseSnapshot prepare(UUID owner, UUID id, UUID courseId) {
        lockActive(owner, id);
        Optional<CourseAttempt> existing = attempts.findById(id);
        if (existing.isPresent()) {
            CourseAttempt attempt = existing.get();
            requireOwner(owner, attempt.getMemberId());
            if (!attempt.getCourseId().equals(courseId)) {
                throw new AppException(RunErrorCode.CONFLICT);
            }
            return snapshot(attempt);
        }
        if (sessions.existsById(id)) { // 이미 자유 러닝으로 준비된 세션
            throw new AppException(RunErrorCode.CONFLICT);
        }
        CourseRouteSnapshot course = courseApi.getRouteForRun(courseId); // 없거나 비활성이면 COURSE-001·002
        CourseAttempt attempt = attempts.save(new CourseAttempt(id, owner, course.courseId(), course.name(),
                course.version(), json.writeValueAsString(course.route()), course.totalDistanceMeters()));
        return snapshot(attempt);
    }

    /** 시작 신호. 같은 startedAt 재시도는 이벤트를 다시 내지 않는다 */
    @Transactional
    public void start(UUID owner, UUID id, Instant startedAt) {
        lockActive(owner, id);
        CourseAttempt attempt = attempts.findByIdAndMemberId(id, owner)
                .orElseThrow(() -> new AppException(RunErrorCode.NOT_FOUND));
        if (startedAt == null || startedAt.isBefore(Instant.EPOCH) || startedAt.isAfter(clock.instant().plusSeconds(300))) {
            throw new AppException(RunErrorCode.INVALID);
        }
        if (attempt.getStartedAt() != null) {
            if (!attempt.getStartedAt().equals(startedAt)) {
                throw new AppException(RunErrorCode.CONFLICT);
            }
            return;
        }
        // DB(timestamptz) 정밀도로 맞춰 기록 삭제 때 보내는 startedAt이 이 이벤트의 occurredAt과 같게 한다
        Instant now = clock.instant().truncatedTo(ChronoUnit.MICROS);
        attempt.start(startedAt, now);
        events.publishEvent(new CourseRunStartedEvent(UuidV7.create(), now, id, attempt.getCourseId(), owner));
        publishRunners(attempt.getCourseId(), now);
    }

    /** 구간 종료 신호(경로 끝 도착·코스만 종료). 자유 러닝·모르는 세션·이미 빠진 시도면 무시한다 */
    @Transactional
    public void segmentEnd(UUID owner, UUID id) {
        locks.member(owner);
        locks.session(id);
        attempts.findByIdAndMemberId(id, owner).filter(CourseAttempt::active)
                .ifPresent(attempt -> release(attempt, "SEGMENT_END"));
    }

    /** 업로드가 다 도착했다. 구간 종료 신호가 없었으면 여기서 뺀다. 호출하는 쪽이 잠금을 갖고 있다 */
    public void releaseOnUpload(UUID id) {
        attempts.findById(id).filter(CourseAttempt::active).ifPresent(attempt -> release(attempt, "UPLOAD"));
    }

    @Transactional(readOnly = true)
    public List<UUID> expiredIds() {
        return attempts.findExpiredIds(clock.instant().minus(ACTIVE_TIMEOUT), PageRequest.of(0, 100));
    }

    /** 시작 후 {@link #ACTIVE_TIMEOUT}이 지나도 구간 종료·업로드가 없는 시도(앱 강제 종료·방치) */
    @Transactional
    public void releaseExpired(UUID id) {
        Optional<UUID> member = attempts.findMemberId(id);
        if (member.isEmpty()) {
            return;
        }
        locks.member(member.get());
        locks.session(id);
        Instant startedBefore = clock.instant().minus(ACTIVE_TIMEOUT);
        attempts.findById(id).filter(attempt -> attempt.active() && attempt.getStartedAt().isBefore(startedBefore))
                .ifPresent(attempt -> release(attempt, "TIMEOUT"));
    }

    /** 업로드 처리 판정. 코스 러닝을 시작한 세션이 아니면 null */
    public CourseOutcome judge(UUID id, List<Input> inputs) {
        return attempts.findById(id).filter(attempt -> attempt.getStartedAt() != null).map(attempt -> {
            CourseRouteSnapshot course = new CourseRouteSnapshot(attempt.getCourseId(), attempt.getCourseName(),
                    route(attempt), attempt.getTotalDistanceMeters(), attempt.getCourseVersion());
            CourseJudge.Judgement judgement = judge.judge(course, inputs);
            return new CourseOutcome(attempt.getCourseId(), attempt.getCourseName(), attempt.getCourseVersion(), attempt.getTotalDistanceMeters(),
                    judgement.completed(), judgement.reason().name(), judgement.recognizedM(), judgement.progressPercent(),
                    judgement.completedAt(), judgement.courseElapsedSeconds(), judgement.courseMovingSeconds(),
                    judgement.reviewEligible());
        }).orElse(null);
    }

    /**
     * 종료 업로드 준비({@link RunService#prepare})의 확인. 코스 러닝인지는 서버에 남은 코스 시도로 정한다.
     * 앱이 재실행돼 코스 정보를 잃고 {@code FREE}로 준비해도 코스 기록으로 판정한다.
     * 코스 시도가 있으면 시작 신호 때와 같은 startedAt이어야 하고, 없는데 {@code COURSE}면 거부한다.
     */
    public void checkPrepare(UUID owner, UUID id, String mode, Instant startedAt) {
        if (!"FREE".equals(mode) && !"COURSE".equals(mode)) {
            throw new AppException(RunErrorCode.INVALID);
        }
        Optional<CourseAttempt> attempt = attempts.findById(id);
        if (attempt.isEmpty()) {
            if ("COURSE".equals(mode)) {
                throw new AppException(RunErrorCode.NOT_FOUND);
            }
            return;
        }
        CourseAttempt course = attempt.get();
        requireOwner(owner, course.getMemberId());
        if (course.getStartedAt() == null || !course.getStartedAt().equals(startedAt)) {
            throw new AppException(RunErrorCode.CONFLICT);
        }
    }

    /** 기록 삭제 때 도전 수를 같은 날짜에서 빼도록 시작 이벤트 시각을 돌려준다 */
    public Optional<Instant> startedEventAt(UUID id) {
        return attempts.findById(id).map(CourseAttempt::getStartedEventAt);
    }

    /** Deletion also covers prepared/started attempts which have no upload session yet. Caller holds ID lock. */
    void requireOwnerIfPresent(UUID owner, UUID id) {
        attempts.findMemberId(id).ifPresent(member -> requireOwner(owner, member));
    }

    /** 기록 삭제: 아직 러너 수에 있으면 빼고 시도를 지운다. 호출하는 쪽이 잠금을 갖고 있다 */
    public void forget(UUID id) {
        attempts.findById(id).ifPresent(attempt -> {
            if (attempt.active()) {
                release(attempt, "DELETED");
            }
            attempts.delete(attempt);
        });
    }

    /** 탈퇴: 세션 없이 준비·시작만 한 시도까지 지운다. 호출하는 쪽이 회원 잠금을 갖고 있다 */
    public void forgetMember(UUID member) {
        for (UUID id : attempts.findIdsByMemberId(member)) {
            locks.session(id);
            forget(id);
        }
    }

    private void release(CourseAttempt attempt, String reason) {
        Instant now = clock.instant();
        attempt.release(now, reason);
        publishRunners(attempt.getCourseId(), now);
    }

    /** version을 먼저 올려 코스 행을 잠근 뒤 센다. 같은 코스의 다른 증감은 이 트랜잭션이 끝날 때까지 기다린다 */
    private void publishRunners(UUID courseId, Instant now) {
        long version = counts.nextVersion(courseId);
        int active = Math.toIntExact(attempts.countActive(courseId));
        events.publishEvent(new CourseActiveRunnersChangedEvent(UuidV7.create(), now, courseId, active, version));
    }

    private void lockActive(UUID owner, UUID id) {
        locks.member(owner);
        if (withdrawnMembers.existsById(owner)) {
            throw new AppException(RunErrorCode.NOT_FOUND);
        }
        locks.session(id);
        if (deletedRecords.existsById(id)) {
            throw new AppException(RunErrorCode.NOT_FOUND);
        }
    }

    private CourseSnapshot snapshot(CourseAttempt attempt) {
        return new CourseSnapshot(attempt.getId(), attempt.getCourseId(), attempt.getCourseName(), route(attempt),
                attempt.getTotalDistanceMeters(), attempt.getCourseVersion());
    }

    private List<GeoPoint> route(CourseAttempt attempt) {
        return List.of(json.readValue(attempt.getRouteJson(), GeoPoint[].class));
    }

    private static void requireOwner(UUID owner, UUID storedOwner) {
        if (!owner.equals(storedOwner)) {
            throw new AppException(RunErrorCode.NOT_FOUND);
        }
    }
}

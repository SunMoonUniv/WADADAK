package com.wadadak.common.storage;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import lombok.RequiredArgsConstructor;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.concurrent.TimeUnit;

/**
 * 발급한 업로드 폼 장부({@code common.photo_uploads}, 개발 정책 7장 사진 업로드).
 * 앱이 저장소에 직접 올려서 서버는 업로드를 보지 못한다. 그래서 폼을 줄 때 키와 받은 사람을 적고, 리뷰·가입에 저장하면 지운다.
 * <ul>
 *   <li>발급 제한: 최근 1시간에 받고 아직 저장하지 않은 폼이 {@value #MAX_PENDING}개면 더 주지 않는다(COMMON-008).
 *       앱은 올리자마자 저장하므로 정상 사용으로는 닿지 않는다</li>
 *   <li>정리: 1시간이 지나도 저장하지 않은 사진은 파일을 지운다. 폼은 10분이면 만료된다</li>
 *   <li>저장: 폼을 받은 사람만, 한 번만 쓸 수 있다. 남이 받은 폼의 사진 키는 들어오지 않는다</li>
 * </ul>
 */
@Component
@RequiredArgsConstructor
public class PhotoUploads {

    static final int MAX_PENDING = 20;
    static final Duration ABANDONED_AFTER = Duration.ofHours(1);
    private static final int CLEANUP_BATCH = 100;

    private final JdbcTemplate jdbc;
    private final ObjectStorage storage;
    private final Clock clock;

    /**
     * 사진 한 장을 올릴 폼. 저장할 때 같은 {@code owner}로 {@link #claim}한다.
     *
     * @param owner 폼을 받는 사람. 회원 ID, 가입 전에는 소셜 계정
     */
    @Transactional
    public UploadForm form(String module, String owner) {
        // 같은 사람의 동시 요청이 서로의 발급을 못 보고 함께 한도를 넘지 않게 줄 세운다. 트랜잭션이 끝나면 풀린다
        jdbc.query("SELECT pg_advisory_xact_lock(hashtextextended(?::text, 0))", (rs, n) -> true, "photo-upload:" + owner);
        Instant now = clock.instant();
        Integer pending = jdbc.queryForObject("SELECT count(*) FROM common.photo_uploads WHERE owner = ? AND created_at > ?",
                Integer.class, owner, Timestamp.from(now.minus(ABANDONED_AFTER)));
        if (pending >= MAX_PENDING) {
            throw new AppException(CommonErrorCode.TOO_MANY_PHOTO_UPLOADS);
        }
        UploadForm form = storage.photoUploadForm(module);
        jdbc.update("INSERT INTO common.photo_uploads (photo_key, owner, created_at) VALUES (?, ?, ?)",
                form.key(), owner, Timestamp.from(now));
        return form;
    }

    /**
     * 사진을 리뷰·가입에 저장한다고 장부에서 지운다. 지운 사진은 정리하지 않는다.
     * 저장하는 쪽 트랜잭션 안에서 부른다. 저장이 롤백되면 장부도 돌아와 나중에 정리된다.
     *
     * @return 모두 {@code owner}가 받은 {@code module} 폼으로 올라와 있으면 true.
     *         남이 받은 폼, 이미 저장했거나 정리된 사진, 올라오지 않은 사진이 하나라도 있으면 false(호출한 쪽이 롤백한다)
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public boolean claim(String module, String owner, Collection<String> keys) {
        for (String key : keys) {
            if (jdbc.update("DELETE FROM common.photo_uploads WHERE photo_key = ? AND owner = ?", key, owner) == 0
                    || !storage.isUploadedPhoto(module, key)) {
                return false;
            }
        }
        return true;
    }

    /** 1시간이 지나도 저장하지 않은 사진을 지운다. 저장소가 안 돼 못 지운 것은 장부에 남겨 다음에 다시 지운다. */
    @Scheduled(initialDelay = 10, fixedDelay = 10, timeUnit = TimeUnit.MINUTES)
    @SchedulerLock(name = "common.photo-upload-cleanup")
    void deleteAbandoned() {
        Timestamp before = Timestamp.from(clock.instant().minus(ABANDONED_AFTER));
        List<String> keys = jdbc.queryForList("SELECT photo_key FROM common.photo_uploads WHERE created_at < ? ORDER BY created_at LIMIT ?",
                String.class, before, CLEANUP_BATCH);
        for (String key : keys) {
            // 장부에서 먼저 지운다. 그 사이 저장(claim)했으면 0건이라 파일을 둔다. 저장 중이면 그 트랜잭션이 끝날 때까지 기다린다
            List<String> owner = jdbc.queryForList("DELETE FROM common.photo_uploads WHERE photo_key = ? AND created_at < ? RETURNING owner",
                    String.class, key, before);
            if (!owner.isEmpty() && !storage.remove(key)) {
                jdbc.update("INSERT INTO common.photo_uploads (photo_key, owner, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
                        key, owner.getFirst(), before);
            }
        }
    }
}

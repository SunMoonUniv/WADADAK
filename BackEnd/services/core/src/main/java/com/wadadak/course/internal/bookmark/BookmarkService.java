package com.wadadak.course.internal.bookmark;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.internal.course.Retention;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * 저장한 코스(정책 문서 4.1 `저장한 코스 API`). 회원은 로그인 토큰으로만 정해 다른 회원의 저장은 보거나 바꿀 수 없다.
 * 같은 요청은 다시 보내도 결과가 같다: 이미 저장한 코스를 다시 저장하면 그대로 두고, 저장하지 않은 코스를 해제해도 오류가 아니다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
class BookmarkService {

    private final BookmarkRepository repository;
    private final MemberApi memberApi;
    private final Clock clock;

    /**
     * 공개 중인 코스만 새로 저장한다(내 코스도 된다). 이미 저장했으면 코스 상태와 상관없이 그대로 둔다.
     * 없는 코스 COURSE-001, 삭제 예정 · 삭제 · 만료 시각이 지나 배치를 기다리는 코스 COURSE-002.
     */
    @Transactional
    void save(UUID memberId, UUID courseId) {
        if (repository.exists(memberId, courseId)) {
            return;
        }
        BookmarkRepository.CourseState course = repository.lockCourse(courseId)
                .orElseThrow(() -> new AppException(CourseErrorCode.COURSE_NOT_FOUND));
        Instant now = clock.instant();
        if (course.status() != CourseStatus.ACTIVE || !now.isBefore(Retention.end(course.expiresAt()))) {
            throw new AppException(CourseErrorCode.COURSE_NOT_AVAILABLE);
        }
        repository.insert(memberId, courseId, now);
    }

    /** 코스 상태와 상관없이 푼다(G5 편집의 여러 개 해제도 같다) */
    @Transactional
    void remove(UUID memberId, Set<UUID> courseIds) {
        repository.delete(memberId, courseIds);
    }

    @Transactional(readOnly = true)
    List<UUID> bookmarked(UUID memberId, Set<UUID> courseIds) {
        return repository.bookmarked(memberId, courseIds);
    }

    @Transactional(readOnly = true)
    CursorSlice<BookmarkItem> list(UUID memberId, BookmarkListRequest request, Cursorable page) {
        CursorSlice<BookmarkItem> slice = repository.list(memberId, request.sortOrDefault(), request.origin(), page);
        Map<UUID, String> nicknames = nicknames(slice.content().stream().map(BookmarkItem::creatorId).collect(Collectors.toSet()));
        return new CursorSlice<>(slice.content().stream()
                .map(item -> item.withCreatorNickname(nicknames.get(item.creatorId())))
                .toList(), slice.nextCursor());
    }

    @Transactional(readOnly = true)
    BookmarkSummary summary(UUID memberId) {
        return repository.summary(memberId, Retention.expiringSoonBefore(LocalDate.ofInstant(clock.instant(), TimeConfig.SEOUL)));
    }

    /** 표시용이라 회원 정보를 받지 못해도 목록은 그대로 돌려준다(개발 정책 4.4). 탈퇴한 등록자는 `탈퇴한 사용자`다 */
    private Map<UUID, String> nicknames(Set<UUID> creatorIds) {
        if (creatorIds.isEmpty()) {
            return Map.of();
        }
        try {
            return memberApi.getProfiles(creatorIds).stream()
                    .collect(Collectors.toMap(MemberProfile::memberId, MemberProfile::nickname, (a, b) -> a));
        } catch (RuntimeException e) {
            log.warn("등록자 프로필 조회 실패. 닉네임 없이 저장한 코스를 돌려준다", e);
            return Map.of();
        }
    }
}

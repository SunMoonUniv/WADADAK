package com.wadadak.review.internal;

import com.wadadak.common.entity.BaseEntity;
import com.wadadak.common.entity.UuidV7;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.util.EnumSet;
import java.util.Set;
import java.util.UUID;

/**
 * 코스 리뷰. 회원당 코스별 1개다(정책 공통 5). 작성 시각({@code createdAt})은 수정해도 바뀌지 않고,
 * 리뷰 이벤트의 {@code createdAt}으로 course 일별 평점이 쌓이는 날짜가 된다(개발 정책 5.6).
 *
 * <p>[읽는 법] 엔티티는 "DB 테이블 한 행 = 자바 객체 하나"로 대응시킨 클래스다.
 * JPA(Hibernate)가 필드 이름을 컬럼 이름으로 바꿔 매핑한다(camelCase → snake_case, 예: {@code safetyRating} → {@code safety_rating}).
 * 테이블 구조는 마이그레이션 SQL({@code db/migration/review/})이 기준이고, 엔티티가 그와 다르면 서버가 뜰 때 검증에서 실패한다.
 */
@Getter // Lombok: 모든 필드의 getXxx()를 자동으로 만든다. setter는 만들지 않아 값은 아래 메서드로만 바뀐다
@Entity // 이 클래스가 DB 테이블과 연결된 엔티티라고 JPA에 알린다
@Table(schema = "review", name = "reviews") // review 스키마의 reviews 테이블
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA가 DB에서 읽어 객체를 만들 때 쓰는 빈 생성자. 외부에서는 못 쓰게 protected
class Review extends BaseEntity<UUID> { // BaseEntity가 created_at·updated_at을 자동으로 채운다

    @Id // PK. DB가 아니라 애플리케이션이 UUID v7로 만든다(write 참고)
    private UUID id;

    private UUID courseId;

    private UUID memberId;

    /** 근거 기록(run 기록 ID). 기록이 삭제돼도 남긴다(B10-1) */
    private UUID sourceRunRecordId;

    // 별점 5개. 범위(1~5)는 요청 단계(ReviewContent의 @Min·@Max)와 DB CHECK 두 곳에서 막는다
    private int rating;
    private int safetyRating;
    private int roadRating;
    private int lightingRating;
    private int amenityRating;

    /** 한줄 후기. 없으면 {@code null} */
    private String content;

    // DB에는 VARCHAR(20)[] 배열로 저장한다. @Enumerated(STRING)이라 enum 이름(예: "NIGHT_VIEW") 그대로 들어간다
    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.ARRAY)
    private Set<ReviewTag> tags;

    /** 이 회원의 이 코스 최고 진행도(%). 근거 기록이 삭제돼도 줄이지 않는다(정책 공통 5) */
    private int bestProgressPercent;

    /**
     * 새 리뷰를 만든다. 생성자 대신 이름 있는 정적 메서드를 써서 "리뷰를 쓴다"는 의도를 드러낸다.
     * 여기서는 객체만 만들고, DB 저장은 서비스가 repository로 한다.
     */
    static Review write(UUID courseId, UUID memberId, UUID sourceRunRecordId, ReviewContent content, int bestProgressPercent) {
        Review review = new Review();
        review.id = UuidV7.create(); // 저장 전에 ID를 알아야 이벤트에 바로 실을 수 있다(개발 정책 6.1)
        review.courseId = courseId;
        review.memberId = memberId;
        review.sourceRunRecordId = sourceRunRecordId;
        review.bestProgressPercent = bestProgressPercent;
        review.apply(content);
        return review;
    }

    /**
     * 별점·항목 평가·후기·태그를 바꾼다. 최고 진행도는 더 높아질 때만 올린다.
     * 엔티티 필드만 바꾸면 트랜잭션이 끝날 때 JPA가 바뀐 부분을 찾아 UPDATE를 보낸다(변경 감지). save()를 다시 부를 필요가 없다.
     */
    void edit(ReviewContent content, int currentBestProgressPercent) {
        apply(content);
        bestProgressPercent = Math.max(bestProgressPercent, currentBestProgressPercent);
    }

    boolean isWrittenBy(UUID memberId) {
        return this.memberId.equals(memberId);
    }

    // 작성·수정이 같은 값을 바꾸므로 한 곳에 모았다
    private void apply(ReviewContent content) {
        rating = content.rating();
        safetyRating = content.safetyRating();
        roadRating = content.roadRating();
        lightingRating = content.lightingRating();
        amenityRating = content.amenityRating();
        this.content = content.text();
        // EnumSet.copyOf는 빈 컬렉션을 받으면 예외라서 빈 경우를 따로 만든다
        tags = content.tags().isEmpty() ? EnumSet.noneOf(ReviewTag.class) : EnumSet.copyOf(content.tags());
    }
}

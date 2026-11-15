package com.wadadak.member.internal.admin;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.paging.NumberedPage;
import com.wadadak.common.region.Region;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.member.MemberErrorCode;
import com.wadadak.member.internal.account.AgreementType;
import com.wadadak.member.internal.account.Member;
import com.wadadak.member.internal.account.MemberRepository;
import com.wadadak.member.internal.account.RunningExperience;
import com.wadadak.member.internal.admin.AdminMemberViews.AdminAgreement;
import com.wadadak.member.internal.admin.AdminMemberViews.AdminMemberDetail;
import com.wadadak.member.internal.admin.AdminMemberViews.AdminMemberRow;
import com.wadadak.member.internal.admin.AdminMemberViews.AdminMemberStats;
import com.wadadak.member.internal.social.SocialProvider;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * 운영자 회원 관리(ADM-1 목록 · ADM-1-1 상세). 정보만 보고 고치지 않는다(2026-11-10 결정).
 * 탈퇴 회원은 개인정보를 지운 행만 남아서 목록 · 숫자 · 상세 모두에서 뺀다. 로그인은 SecurityConfig의 운영자 체인이 맡는다.
 *
 * <p>목록은 SQL을 직접 쓴다({@link JdbcClient}). 필터가 붙고 전체 개수도 같이 받아야 해서, 리뷰 운영자 목록과 같은 방식이다.
 */
@Service
@RequiredArgsConstructor
class AdminMemberService {

    private final JdbcClient jdbc;
    private final MemberRepository members;
    private final RegionDirectory regions;
    private final ObjectStorage storage;
    private final Clock clock;

    AdminMemberStats stats() {
        LocalDate today = LocalDate.now(clock.withZone(TimeConfig.SEOUL));
        return jdbc.sql("""
                        SELECT count(*) AS total,
                               count(*) FILTER (WHERE created_at >= :weekStart) AS week,
                               count(*) FILTER (WHERE created_at >= :monthStart) AS month
                        FROM member.members
                        WHERE status = 'ACTIVE'""")
                .param("weekStart", startOf(today.with(DayOfWeek.MONDAY)))
                .param("monthStart", startOf(today.withDayOfMonth(1)))
                .query((rs, rowNum) -> new AdminMemberStats(rs.getLong("total"), rs.getLong("week"), rs.getLong("month")))
                .single();
    }

    /**
     * 최근 가입 순.
     *
     * @param provider   이 가입 방식만. {@code null}이면 전체
     * @param experience 이 러닝 경력만. {@code null}이면 전체
     */
    NumberedPage<AdminMemberRow> list(SocialProvider provider, RunningExperience experience, int page, int size) {
        // 조건이 있을 때만 붙인다. "? IS NULL OR …"로 쓰면 PostgreSQL이 null 파라미터의 타입을 몰라 실패한다
        String sql = """
                SELECT id, nickname, profile_image_key, social_provider, region_code, affiliation, running_experience,
                       created_at, count(*) OVER () AS total
                FROM member.members
                WHERE status = 'ACTIVE'"""
                + (provider == null ? "" : " AND social_provider = :provider")
                + (experience == null ? "" : " AND running_experience = :experience")
                + " ORDER BY created_at DESC, id DESC LIMIT :limit OFFSET :offset";
        JdbcClient.StatementSpec query = jdbc.sql(sql).param("limit", size).param("offset", page * size);
        if (provider != null) {
            query = query.param("provider", provider.name());
        }
        if (experience != null) {
            query = query.param("experience", experience.name());
        }
        long[] total = {0};
        record Row(UUID id, String nickname, String photoKey, SocialProvider provider, String regionCode,
                   String affiliation, RunningExperience experience, Instant joinedAt) {
        }
        List<Row> rows = query.query((rs, rowNum) -> {
            total[0] = rs.getLong("total");
            return new Row(rs.getObject("id", UUID.class), rs.getString("nickname"), rs.getString("profile_image_key"),
                    SocialProvider.valueOf(rs.getString("social_provider")), rs.getString("region_code"),
                    rs.getString("affiliation"), RunningExperience.valueOf(rs.getString("running_experience")),
                    instant(rs, "created_at"));
        }).list();
        // 지역 이름은 한 번에 찾는다(줄마다 찾으면 N번)
        Map<String, Region> regionsByCode = regions.findSigungus(rows.stream().map(Row::regionCode).collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(Region::code, Function.identity()));
        return new NumberedPage<>(rows.stream()
                .map(r -> new AdminMemberRow(r.id(), r.nickname(), photoUrl(r.photoKey()), r.provider(),
                        regionsByCode.get(r.regionCode()), r.affiliation(), r.experience(), r.joinedAt()))
                .toList(), total[0]);
    }

    /** @throws AppException MEMBER-011 없거나 탈퇴한 회원 */
    @Transactional(readOnly = true)
    AdminMemberDetail detail(UUID memberId) {
        Member m = members.findById(memberId)
                .filter(member -> !member.isWithdrawn())
                .orElseThrow(() -> new AppException(MemberErrorCode.MEMBER_NOT_FOUND));
        return new AdminMemberDetail(m.getId(), m.getNickname(), m.getBio(),
                regions.findSigungu(m.getRegionCode()).orElse(null), m.getRegionCode(),
                m.getAffiliation(), m.getRunningExperience(), m.getProfileImageKey(), photoUrl(m.getProfileImageKey()),
                m.getSocialProvider(), m.getSocialId(), m.getCreatedAt(), m.getUpdatedAt(), m.getNicknameChangedAt(),
                m.getBodyInfo(), m.isInfoPublic(), m.isProfileSearchable(), agreements(memberId));
    }

    /** 동의는 쌓기만 해서, 항목마다 가장 최근 행이 지금 상태다(DISTINCT ON: 항목별로 정렬한 첫 행만). */
    private List<AdminAgreement> agreements(UUID memberId) {
        return jdbc.sql("""
                        SELECT DISTINCT ON (type) type, agreed, version, created_at
                        FROM member.agreements
                        WHERE member_id = :memberId
                        ORDER BY type, created_at DESC, id DESC""")
                .param("memberId", memberId)
                .query((rs, rowNum) -> new AdminAgreement(AgreementType.valueOf(rs.getString("type")),
                        rs.getBoolean("agreed"), rs.getString("version"), instant(rs, "created_at")))
                .list().stream()
                .sorted(Comparator.comparing(AdminAgreement::type)) // 가입 화면의 항목 순서
                .toList();
    }

    private String photoUrl(String key) {
        return key == null ? null : storage.url(key);
    }

    private static OffsetDateTime startOf(LocalDate date) {
        return date.atStartOfDay(TimeConfig.SEOUL).toOffsetDateTime().withOffsetSameInstant(ZoneOffset.UTC);
    }

    private static Instant instant(ResultSet rs, String column) throws SQLException {
        return rs.getObject(column, OffsetDateTime.class).toInstant();
    }
}

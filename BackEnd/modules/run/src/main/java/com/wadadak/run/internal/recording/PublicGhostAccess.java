package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.event.member.MemberVisibilityChangedEvent;
import com.wadadak.ranking.GhostCandidate;
import com.wadadak.run.RunErrorCode;
import java.util.UUID;
import java.util.stream.Stream;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
class PublicGhostAccess {
    private final RunLocks locks;
    private final JdbcTemplate db;
    private final WithdrawnRunMemberRepository withdrawals;
    PublicGhostAccess(RunLocks locks, JdbcTemplate db, WithdrawnRunMemberRepository withdrawals) {
        this.locks=locks;this.db=db;this.withdrawals=withdrawals;
    }
    /** Always acquire both member locks in stable order before any duel/source session lock. */
    void lock(UUID requester, GhostCandidate candidate) {
        lockMembers(requester,candidate);
        if(withdrawals.existsById(requester) || withdrawals.existsById(candidate.memberId())) unavailable();
        boolean visible=db.queryForObject("SELECT COALESCE((SELECT visible FROM run.member_visibility_copies WHERE member_id=?),true)",Boolean.class,candidate.memberId());
        if(!visible) unavailable();
    }
    void lockMembers(UUID requester,GhostCandidate candidate){
        if(requester.equals(candidate.memberId())) unavailable();
        Stream.of(requester,candidate.memberId()).sorted().forEach(locks::member);
    }
    @Transactional
    public void forget(UUID member){locks.member(member);db.update("DELETE FROM run.member_visibility_copies WHERE member_id=?",member);}
    @Transactional
    public void visibility(MemberVisibilityChangedEvent event) {
        locks.member(event.memberId());
        if(withdrawals.existsById(event.memberId())) return;
        db.update("""
            INSERT INTO run.member_visibility_copies AS v(member_id,visible,source_version) VALUES (?,?,?)
            ON CONFLICT(member_id) DO UPDATE SET visible=EXCLUDED.visible,
                source_version=EXCLUDED.source_version,updated_at=now()
            WHERE v.source_version<EXCLUDED.source_version
            """,event.memberId(),event.visible(),event.version());
    }
    static void unavailable(){throw new AppException(RunErrorCode.GHOST_UNAVAILABLE);}
}

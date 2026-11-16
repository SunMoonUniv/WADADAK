package com.wadadak.member.internal.account;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import java.util.UUID;

public interface AgreementRepository extends JpaRepository<Agreement, UUID> {

    /** 탈퇴하면 동의 이력도 함께 지운다(2026-11-02 사용자 결정, 정책 문서 공통 4 미결 항목). */
    @Modifying // SELECT가 아니라 DELETE를 실행하는 쿼리라는 표시
    @Query("delete from Agreement a where a.memberId = :memberId")
    void deleteByMemberId(UUID memberId);
}

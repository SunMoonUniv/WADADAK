package com.wadadak.member.internal.account;

import com.wadadak.common.exception.AppException;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberErrorCode;
import com.wadadak.member.MemberProfile;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Set;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "app.stub.member", havingValue = "false", matchIfMissing = true)
class MemberService implements MemberApi {

    private final MemberRepository memberRepository;

    @Override
    @Transactional(readOnly = true)
    public List<MemberProfile> getProfiles(Set<UUID> memberIds) {
        if (memberIds.size() > MAX_IDS) {
            throw new AppException(MemberErrorCode.TOO_MANY_MEMBER_IDS);
        }
        // ponytail: 프로필 사진 URL은 업로드(ObjectStorage) 기능과 함께 채운다.
        return memberRepository.findAllById(memberIds).stream()
                .map(m -> m.isWithdrawn()
                        ? new MemberProfile(m.getId(), MemberProfile.WITHDRAWN_NICKNAME, null, true)
                        : new MemberProfile(m.getId(), m.getNickname(), null, false))
                .toList();
    }
}

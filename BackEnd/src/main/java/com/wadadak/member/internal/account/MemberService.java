package com.wadadak.member.internal.account;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.storage.ObjectStorage;
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
    private final ObjectStorage storage;

    @Override
    @Transactional(readOnly = true)
    public List<MemberProfile> getProfiles(Set<UUID> memberIds) {
        if (memberIds.size() > MAX_IDS) {
            throw new AppException(MemberErrorCode.TOO_MANY_MEMBER_IDS);
        }
        return memberRepository.findAllById(memberIds).stream()
                .map(m -> m.isWithdrawn()
                        ? new MemberProfile(m.getId(), MemberProfile.WITHDRAWN_NICKNAME, null, true)
                        : new MemberProfile(m.getId(), m.getNickname(),
                                m.getProfileImageKey() == null ? null : storage.url(m.getProfileImageKey()), false))
                .toList();
    }
}

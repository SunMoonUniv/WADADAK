package com.wadadak.member.internal.account;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.stub.StubImplementation;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberErrorCode;
import com.wadadak.member.MemberProfile;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Set;
import java.util.UUID;

@Component
@ConditionalOnProperty(name = "app.stub.member", havingValue = "true")
class MemberApiStub implements MemberApi, StubImplementation {

    @Override
    public List<MemberProfile> getProfiles(Set<UUID> memberIds) {
        if (memberIds.size() > MAX_IDS) {
            throw new AppException(MemberErrorCode.TOO_MANY_MEMBER_IDS);
        }
        return memberIds.stream()
                .map(id -> new MemberProfile(id, "러너-" + id.toString().substring(0, 4), null, false))
                .toList();
    }
}

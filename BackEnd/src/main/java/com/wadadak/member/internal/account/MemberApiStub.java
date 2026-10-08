package com.wadadak.member.internal.account;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.stub.StubImplementation;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberErrorCode;
import com.wadadak.member.MemberProfile;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

@Component
@ConditionalOnProperty(name = "app.stub.member", havingValue = "true")
class MemberApiStub implements MemberApi, StubImplementation {

    @Override
    public Map<UUID, MemberProfile> getProfiles(Set<UUID> memberIds) {
        if (memberIds.size() > MAX_IDS) {
            throw new AppException(MemberErrorCode.TOO_MANY_MEMBER_IDS);
        }
        return memberIds.stream().collect(Collectors.toMap(Function.identity(),
                id -> new MemberProfile(id, "러너-" + id.toString().substring(0, 4), null, false)));
    }
}

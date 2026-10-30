package com.wadadak.member.internal.search;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.region.Region;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.member.internal.account.Member;
import com.wadadak.member.internal.account.MemberRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.text.Normalizer;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * 러너 검색(G7, SEA-05). 프로필 검색 허용 설정을 member가 가지고 있어 member가 직접 찾는다.
 *
 * <p>[흐름] 검색어를 비교용 키로 바꾼다 → 한 쪽과 전체 수를 센다 → 활동 지역 이름 · 사진 주소를 붙인다.
 */
@Service
@RequiredArgsConstructor
class RunnerSearchService {

    /** 검색어 최소 글자 수(SEA-01). 공백은 세지 않는다 */
    static final int MIN_LENGTH = 2;

    private static final Pattern WHITESPACE = Pattern.compile("\\s+");

    private final MemberRepository memberRepository;
    private final RegionDirectory regions;
    private final ObjectStorage storage;

    @Transactional(readOnly = true)
    RunnerSearchResult search(String query, UUID requesterId, Cursorable page) {
        String key = key(query);
        int offset = page.offset(); // 잘못된 커서는 조회 전에 거른다
        List<Member> members = memberRepository.searchRunners(key, offset, page.size());
        int total = memberRepository.countRunners(key);

        Map<String, Region> regionByCode = regionsOf(members);
        List<RunnerSearchResult.Runner> runners = members.stream()
                .map(m -> runner(m, regionByCode.get(m.getRegionCode()), requesterId))
                .toList();
        int next = offset + members.size();
        return new RunnerSearchResult(total, runners, next < total ? String.valueOf(next) : null);
    }

    /**
     * 검색어를 닉네임과 비교할 키로 바꾼다. 기기마다 한글이 조합형(NFD)으로 올 수 있어 NFC로 맞추고, 공백을 빼고 소문자로 만든다.
     * 닉네임은 공백 없는 한글(완성형) · 영문 · 숫자라 그대로 비교한다.
     *
     * @throws AppException COMMON-001 — 공백을 빼고 {@value #MIN_LENGTH}글자 미만
     */
    private static String key(String query) {
        String key = WHITESPACE.matcher(Normalizer.normalize(query, Normalizer.Form.NFC)).replaceAll("").toLowerCase(Locale.ROOT);
        if (key.codePointCount(0, key.length()) < MIN_LENGTH) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "검색어는 공백을 빼고 " + MIN_LENGTH + "글자 이상이어야 합니다.");
        }
        return key;
    }

    /** 이 쪽 회원들의 활동 지역을 한 번에 찾는다. 지역 목록에서 사라진 코드는 빠진다 */
    private Map<String, Region> regionsOf(List<Member> members) {
        return regions.findSigungus(members.stream().map(Member::getRegionCode).collect(Collectors.toSet())).stream()
                .collect(Collectors.toMap(Region::code, Function.identity()));
    }

    private RunnerSearchResult.Runner runner(Member member, Region region, UUID requesterId) {
        String photoUrl = member.getProfileImageKey() == null ? null : storage.url(member.getProfileImageKey());
        return new RunnerSearchResult.Runner(member.getId(), member.getNickname(), photoUrl, region,
                member.getRunningExperience(), member.getId().equals(requesterId));
    }
}

package com.wadadak.course.internal.planner;

import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanForm.StartKind;
import com.wadadak.course.internal.planner.SentenceRules.Numbers;
import com.wadadak.course.internal.planner.SentenceRules.Spans;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 문장 → 폼 규칙. 시험 문장 75개({@code planner/sentences.json}, 칸별 정답)는 {@code utilfile/_스크립트/course_planner/form_cases.py}에서
 * 옮겼다. 채점은 {@code form_eval.py}와 같다.
 */
class SentenceRulesTest {

    /** 시험 문장. 무관 요청(on false)은 text만 있다 */
    record Sentence(int id, String set, String text, boolean on, StartKind start, Shape shape, Set<Pref> prefer,
                    Integer distanceM, Integer durationMin, String startName, String endName, String viaName) {
    }

    static final List<Sentence> SENTENCES = read("planner/sentences.json", new TypeReference<>() {
    });

    static <T> T read(String path, TypeReference<T> type) {
        try (InputStream in = new ClassPathResource(path).getInputStream()) {
            return JsonMapper.builder().build().readValue(in, type);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    static List<Sentence> courseRequests() {
        return SENTENCES.stream().filter(Sentence::on).toList();
    }

    @Test
    void readsEveryDistanceAndDuration() {
        List<Sentence> requests = courseRequests();

        assertThat(requests).hasSize(67);
        for (Sentence s : requests) {
            assertThat(SentenceRules.numbers(s.text())).as(s.id() + " " + s.text())
                    .isEqualTo(new Numbers(s.distanceM(), s.durationMin()));
        }
    }

    /** 출발 · 도착 · 경유 이름 201칸(67문장 × 3). 정답 이름을 포함하거나(선문대 정문 ⊇ 선문대), 정답에 포함되는 두 글자 이상이면 맞음 */
    @Test
    void readsEveryPlaceName() {
        List<String> misses = new ArrayList<>();
        int checked = 0;
        for (Sentence s : courseRequests()) {
            Spans got = SentenceRules.spans(s.text());
            boolean namedStart = s.start() == StartKind.PLACE;
            checked += 3;
            if (!nameOk(got.start(), s.startName(), s.startName() == null && !namedStart)) {
                misses.add(s.id() + " 출발 " + s.startName() + " ← " + got.start());
            }
            if (!nameOk(got.end(), s.endName(), s.endName() == null)) {
                misses.add(s.id() + " 도착 " + s.endName() + " ← " + got.end());
            }
            if (!nameOk(got.via(), s.viaName(), s.viaName() == null)) {
                misses.add(s.id() + " 경유 " + s.viaName() + " ← " + got.via());
            }
        }

        assertThat(checked).isEqualTo(201);
        assertThat(misses).isEmpty();
    }

    private static boolean nameOk(String got, String want, boolean wantNone) {
        if (wantNone) {
            return got == null;
        }
        if (got == null || got.isEmpty()) {
            return false;
        }
        String g = got.toLowerCase(Locale.ROOT);
        String w = want == null ? "" : want.toLowerCase(Locale.ROOT);
        return g.contains(w) || want != null && w.contains(g) && got.length() >= 2;
    }

    /** 규칙만(Jev 없음)으로 출발 · 모양 · 선호가 모두 맞는 비율. 시험 보고 0.75(보완 전) */
    @Test
    void rulesAloneGetMostFormsRight() {
        List<Sentence> requests = courseRequests();
        long allOk = requests.stream().filter(s -> {
            StartKind start = SentenceRules.spans(s.text()).start() != null ? StartKind.PLACE : StartKind.CURRENT;
            return start == s.start() && SentenceRules.keywordShape(s.text()) == s.shape()
                    && SentenceRules.keywordPrefs(s.text()).equals(s.prefer());
        }).count();

        assertThat((double) allOk / requests.size()).isGreaterThanOrEqualTo(0.75);
    }

    @Test
    void fixesFromTheTest() {
        assertThat(SentenceRules.spans("선문대 정문에서 출발해서 5km 정도 한 바퀴").start()).isEqualTo("선문대 정문");
        assertThat(SentenceRules.spans("초보라서 2km만, 공원 안에서 돌고 싶어 아산 곡교천").start()).isEqualTo("곡교천");
        assertThat(SentenceRules.spans("수원 광교호수공원 둘레로 6km, 오르막 없는 쪽으로").start()).isEqualTo("광교호수공원");
        assertThat(SentenceRules.spans("광안대교 보면서 해변 따라 4km").start()).isEqualTo("광안대교");
        assertThat(SentenceRules.spans("땀 좀 빼고 싶은데 동네 한 바퀴").start()).isNull();
        assertThat(SentenceRules.spans("평평한 길로 하프 거리").start()).isNull();
        // "왕복" 앞 단어가 "들르는"처럼 꾸미는 말이면 장소가 아니다
        assertThat(SentenceRules.spans("30분 정도 편의점 들르는 왕복 코스").start()).isNull();
        assertThat(SentenceRules.spans("독립기념관 왕복 8km").start()).isEqualTo("독립기념관");
        // "…부터"도 출발이다. 건물 이름은 앞 단어와 붙인다. 때를 말하는 "지금부터"는 장소가 아니다
        assertThat(SentenceRules.spans("평평하고 사람 많이 안다니는 선문대 인문관부터 3km 코스").start()).isEqualTo("선문대 인문관");
        assertThat(SentenceRules.spans("천안역부터 5km 한 바퀴").start()).isEqualTo("천안역");
        assertThat(SentenceRules.spans("지금부터 30분 달릴 코스").start()).isNull();
        assertThat(SentenceRules.keywordPrefs("평평하고 사람 많이 안다니는 선문대 인문관부터 3km 코스")).containsExactly(Pref.FLAT);
        assertThat(SentenceRules.keywordPrefs("횡단보도 덜 건너게 5km")).doesNotContain(Pref.SIDEWALK);
        assertThat(SentenceRules.keywordPrefs("보도블록 깔린 길로만 7km")).contains(Pref.SIDEWALK);
        // Figma A7-1 예시. 키가 없어 규칙만 써도 큰길 피하기를 읽는다
        assertThat(SentenceRules.keywordPrefs("선문대에서 큰길 피해서 한 바퀴")).containsExactly(Pref.AVOID_ARTERIAL);
    }

    @Test
    void koreanNumbersAndHugeNumbers() {
        assertThat(SentenceRules.koNumber("십오")).isEqualTo(15);
        assertThat(SentenceRules.koNumber("이십")).isEqualTo(20);
        assertThat(SentenceRules.koNumber("오")).isEqualTo(5);
        assertThat(SentenceRules.koNumber("선")).isNull();
        // 아주 긴 숫자도 오류 없이 읽는다. 범위 밖은 생성 요청 검증이 거절한다
        assertThat(SentenceRules.numbers("99999999999999km 99999999999시간"))
                .isEqualTo(new Numbers(Integer.MAX_VALUE, Integer.MAX_VALUE));
    }
}

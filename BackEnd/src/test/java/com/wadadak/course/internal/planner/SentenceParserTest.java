package com.wadadak.course.internal.planner;

import com.wadadak.course.internal.planner.JevClient.Answer;
import com.wadadak.course.internal.planner.JevClient.JevAnswers;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanForm.Start;
import com.wadadak.course.internal.planner.PlanForm.StartKind;
import com.wadadak.course.internal.planner.SentenceRulesTest.Sentence;
import org.junit.jupiter.api.Test;
import tools.jackson.core.type.TypeReference;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 규칙 + Jev 합치기. Jev는 부르지 않고 시험 때 받은 응답({@code planner/jev-answers.json}, {@code jev-1.14.0},
 * {@code form_eval_jev_en_raw.json})을 쓴다. 채점은 {@code form_hybrid.py}와 같다.
 */
class SentenceParserTest {

    private static final Map<Integer, JevAnswers> RECORDED = SentenceRulesTest.read("planner/jev-answers.json",
                    new TypeReference<List<Recorded>>() {
                    }).stream()
            .collect(Collectors.toMap(Recorded::id, r -> new JevAnswers(r.answers())));

    private record Recorded(int id, Map<String, Answer> answers) {
    }

    private static Optional<JevAnswers> jev(Sentence s) {
        return Optional.of(RECORDED.get(s.id()));
    }

    /** 출발 · 모양 · 선호 모두 맞음. 시험 보고 0.87(58/67) */
    @Test
    void mostFormsAreRightWithJev() {
        List<Sentence> requests = SentenceRulesTest.courseRequests();
        long allOk = requests.stream().filter(s -> {
            PlanForm f = SentenceParser.form(s.text(), jev(s));
            return f.start().kind() == s.start() && f.shape() == s.shape() && f.prefer().equals(s.prefer());
        }).count();

        assertThat(allOk).as("%d/%d", allOk, requests.size()).isGreaterThanOrEqualTo(58);
    }

    /** 무관 요청 구분. 시험 보고 0.99(74/75) */
    @Test
    void tellsOffTopicSentences() {
        long right = SentenceRulesTest.SENTENCES.stream()
                .filter(s -> SentenceParser.onTopic(s.text(), jev(s)) == s.on()).count();

        assertThat(right).isGreaterThanOrEqualTo(74);
    }

    /**
     * 틀린 값을 채운 칸: 무관 판정이 틀림, 출발 · 모양이 틀림, 없는 선호를 붙임, 거리 · 시간이 틀림.
     * 못 읽어 비워 둔 칸(선호 누락 등)은 사용자가 채우므로 세지 않는다.
     */
    @Test
    void fillsFewWrongValues() {
        List<String> wrong = new ArrayList<>();
        for (Sentence s : SentenceRulesTest.SENTENCES) {
            PlanForm f = SentenceParser.fill(s.text(), jev(s));
            if ((f.message() == null) != s.on()) {
                wrong.add(s.id() + " 무관 판정");
                continue;
            }
            if (!s.on()) {
                continue;
            }
            if (f.start().kind() != s.start()) {
                wrong.add(s.id() + " 출발");
            }
            if (f.shape() != s.shape()) {
                wrong.add(s.id() + " 모양 " + f.shape());
            }
            f.prefer().stream().filter(p -> !s.prefer().contains(p)).forEach(p -> wrong.add(s.id() + " 선호 " + p));
            if (f.distanceM() != null && !f.distanceM().equals(s.distanceM())) {
                wrong.add(s.id() + " 거리");
            }
            if (f.durationMin() != null && !f.durationMin().equals(s.durationMin())) {
                wrong.add(s.id() + " 시간");
            }
        }

        assertThat(wrong).as(wrong.toString()).hasSizeLessThanOrEqualTo(4);
    }

    @Test
    void figmaExampleWithoutJev() {
        PlanForm form = SentenceParser.fill("선문대에서 큰길 피해서 한 바퀴", Optional.empty());

        assertThat(form).isEqualTo(new PlanForm(new Start(StartKind.PLACE, "선문대"), Shape.LOOP, null, null, null, null,
                Set.of(Pref.AVOID_ARTERIAL), null));
    }

    @Test
    void placeNamesGoToTheirShape() {
        PlanForm oneWay = SentenceParser.fill("아산역에서 선문대까지 뛰어갈래", Optional.empty());
        assertThat(oneWay.shape()).isEqualTo(Shape.POINT_TO_POINT);
        assertThat(oneWay.endQuery()).isEqualTo("선문대");

        PlanForm via = SentenceParser.fill("광화문에서 출발해서 남산 찍고 돌아오는 코스", Optional.empty());
        assertThat(via.shape()).isEqualTo(Shape.VIA);
        assertThat(via.viaQuery()).isEqualTo("남산");
        assertThat(via.endQuery()).isNull();
    }

    @Test
    void offTopicWithoutJevUsesKeywords() {
        PlanForm form = SentenceParser.fill("주식 추천 좀 해줘", Optional.empty());

        assertThat(form.message()).isEqualTo(SentenceParser.OFF_TOPIC);
        assertThat(form.start()).isNull();
        assertThat(form.shape()).isNull();
    }

    /** 규칙이 "오르막 아닌"을 평지로 읽으면 Jev가 오르막이라 해도 붙이지 않는다 */
    @Test
    void jevCannotAddHillyWhenRulesReadFlat() {
        Map<String, Answer> answers = new HashMap<>(RECORDED.get(1).answers());
        answers.put("pref_hilly", new Answer(0.97, null, null));

        PlanForm form = SentenceParser.form("오르막아닌 5km 코스", Optional.of(new JevAnswers(answers)));

        assertThat(form.prefer()).contains(Pref.FLAT).doesNotContain(Pref.HILLY);
    }

    /** Jev가 장소라는데 이름을 못 읽으면 장소 칸을 비운다(사용자가 채움) */
    @Test
    void jevPlaceWithoutNameLeavesTheNameEmpty() {
        JevAnswers named = RECORDED.get(1); // start: named_place
        PlanForm form = SentenceParser.form("코스 만들어줘", Optional.of(named));

        assertThat(form.start()).isEqualTo(new Start(StartKind.PLACE, null));
    }
}

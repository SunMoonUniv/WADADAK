package com.wadadak.course.internal.planner;

import com.wadadak.course.internal.planner.JevClient.JevAnswers;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanForm.Start;
import com.wadadak.course.internal.planner.PlanForm.StartKind;
import com.wadadak.course.internal.planner.SentenceRules.Numbers;
import com.wadadak.course.internal.planner.SentenceRules.Spans;
import org.springframework.stereotype.Component;

import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * 문장으로 폼을 채운다(B3 자동 생성 문장 입력). 규칙({@link SentenceRules})이 먼저 읽고 Jev({@link JevClient})가 놓친 칸을 보충한다.
 * 사용자가 폼에서 확인 · 수정하므로 못 읽은 거리 · 시간은 비워 두고, 출발 · 모양은 기본값(현재 위치 · 한 바퀴)으로 채운다.
 *
 * <p>합치는 규칙(시험 문장 75개에서 출발 · 모양 · 선호 모두 맞음 0.87, {@code form_hybrid.py}):
 * <ul>
 *     <li>거리 · 시간 · 장소 이름: 규칙만</li>
 *     <li>출발: Jev 선택. Jev가 없으면 장소 이름을 읽었을 때 PLACE</li>
 *     <li>모양: 규칙 단어가 있으면 그것, 없으면 Jev 확신 0.8 이상일 때 Jev, 아니면 LOOP</li>
 *     <li>선호: 규칙 ∪ Jev 0.9 이상. Jev만 쓰면 장소 이름만 보고 선호를 붙이는 일이 많아 문턱을 높였다</li>
 *     <li>무관 요청: 숫자가 있으면 코스 요청. 없으면 Jev 0.5 미만일 때만 무관, Jev가 없으면 규칙 단어로</li>
 * </ul>
 */
@Component
class SentenceParser {

    static final String OFF_TOPIC = "코스와 관련된 문장이 아니에요. 출발지 · 거리 · 모양을 말해 주세요.";

    private static final Map<String, Shape> JEV_SHAPE = Map.of(
            "loop", Shape.LOOP, "out_and_back", Shape.OUT_AND_BACK, "point_to_point", Shape.POINT_TO_POINT, "via_landmark", Shape.VIA);

    private final JevClient jev;

    SentenceParser(JevClient jev) {
        this.jev = jev;
    }

    PlanForm parse(String text) {
        return fill(text, jev.ask(text));
    }

    static PlanForm fill(String text, Optional<JevAnswers> jev) {
        return onTopic(text, jev) ? form(text, jev) : new PlanForm(null, null, null, null, null, null, Set.of(), OFF_TOPIC);
    }

    static boolean onTopic(String text, Optional<JevAnswers> jev) {
        Numbers numbers = SentenceRules.numbers(text);
        return numbers.distanceM() != null || numbers.durationMin() != null
                || jev.map(a -> a.noul("on_topic") >= 0.5).orElseGet(() -> SentenceRules.onTopicByKeyword(text));
    }

    /** 코스 요청이라고 보고 칸을 채운다 */
    static PlanForm form(String text, Optional<JevAnswers> jev) {
        Numbers numbers = SentenceRules.numbers(text);
        Spans spans = SentenceRules.spans(text);
        boolean fromPlace = jev.map(a -> a.choice("start").equals("named_place")).orElse(spans.start() != null);
        // Jev는 장소라는데 이름을 못 읽었으면 장소 칸을 비워 사용자가 채우게 한다
        Start start = fromPlace ? new Start(StartKind.PLACE, spans.start()) : new Start(StartKind.CURRENT, null);

        Shape shape = SentenceRules.keywordShape(text);
        if (shape == Shape.LOOP) {
            shape = jev.filter(a -> a.confidence("shape") >= 0.8).map(a -> JEV_SHAPE.get(a.choice("shape"))).orElse(Shape.LOOP);
        }

        Set<Pref> prefer = SentenceRules.keywordPrefs(text);
        jev.ifPresent(a -> {
            for (Pref p : Pref.values()) {
                if (a.noul("pref_" + p.name().toLowerCase(Locale.ROOT)) >= 0.9) {
                    prefer.add(p);
                }
            }
        });

        return new PlanForm(start, shape,
                shape == Shape.POINT_TO_POINT ? spans.end() : null,
                shape == Shape.VIA ? spans.via() : null,
                numbers.distanceM(), numbers.durationMin(), prefer, null);
    }
}

package com.wadadak.course.internal.planner;

import tools.jackson.databind.JsonNode;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * 분석 로그 CSV의 한 줄을 엑셀에서 바로 읽히는 칸으로 푼다({@link AdminPlannerLogQueries#csv}).
 *
 * <p>DB에는 폼 · Jev 답 · 후보가 JSON 덩어리로 있다. 그대로 넣으면 칸 하나에 긴 JSON이 들어가 읽기 어렵다.
 * 그래서 폼은 칸별로(출발 · 모양 · 거리 …), Jev 답은 고른 답과 확률만, 후보는 1~3번 후보의 지표를 칸으로 나눈다.
 * 값은 사람이 읽는 말(한 바퀴 · 평지)로 바꾸고, 비율은 %(소수 첫째 자리), 거리는 km다. 없는 값은 빈칸이다.
 */
final class PlannerLogCsv {

    private PlannerLogCsv() {
    }

    /** 칸으로 푼 폼의 순서. 바뀐 칸 비교도 이 단위로 한다 */
    private static final List<String> FORM_LABELS = List.of("출발", "모양", "거리(km)", "시간(분)", "도착지·경유지", "원하는 길");
    /** 후보 칸: 머리글 · 후보 JSON 키 · 비율이면 true(%로 바꾼다) */
    private static final List<Object[]> CANDIDATE_COLUMNS = List.of(
            new Object[]{"거리(km)", "distanceMeters", false}, new Object[]{"큰길(%)", "arterialRatio", true},
            new Object[]{"되돌아옴(%)", "retraceRatio", true}, new Object[]{"오르막(m)", "ascentMeters", false},
            new Object[]{"편의점", "storeCount", false}, new Object[]{"화장실", "toiletCount", false},
            new Object[]{"인도(%)", "sidewalkRatio", true}, new Object[]{"강변(%)", "riverRatio", true},
            new Object[]{"밝은 길(%)", "litRatio", true});
    static final int MAX_CANDIDATES = 3;

    private static final Map<String, String> SHAPE = Map.of(
            "LOOP", "한 바퀴", "OUT_AND_BACK", "왕복", "POINT_TO_POINT", "편도", "VIA", "경유");
    /** Jev의 모양 · 출발 답(영어 보기) */
    private static final Map<String, String> JEV_CHOICE = Map.of(
            "loop", "한 바퀴", "out_and_back", "왕복", "point_to_point", "편도", "via_landmark", "경유",
            "named_place", "장소", "current_location", "현재 위치");
    /** 원하는 길. 키는 Pref 이름의 소문자(Jev 질문 id의 pref_ 뒤와 같다) */
    private static final Map<String, String> PREF = Map.ofEntries(
            Map.entry("flat", "평지"), Map.entry("hilly", "오르막"), Map.entry("sidewalk", "인도"),
            Map.entry("avoid_arterial", "큰길 피하기"), Map.entry("store_on_route", "편의점 들르기"),
            Map.entry("toilet_on_route", "화장실 들르기"), Map.entry("river", "강변"), Map.entry("park", "공원"),
            Map.entry("no_retrace", "같은 길 반복 없이"), Map.entry("lit", "밝은 길"));
    private static final Map<String, String> REASON = Map.of(
            "PLACE_NOT_FOUND", "장소 못 찾음", "PLACE_TOO_FAR", "장소가 너무 멂", "NO_CANDIDATES", "길 없음",
            "SIMILAR_EXISTS", "비슷한 코스 있음");

    /** 머리글 한 줄 */
    static List<String> header() {
        List<String> h = new ArrayList<>(List.of("문장 시각", "사용자", "문장",
                "Jev", "Jev 코스 관련(%)", "Jev 모양", "Jev 모양(%)", "Jev 출발", "Jev 출발(%)", "Jev 원하는 길(50% 이상)"));
        FORM_LABELS.forEach(l -> h.add("채운 폼 " + l));
        h.add("채우기(ms)");
        h.add("코스 찾기 시각");
        FORM_LABELS.forEach(l -> h.add("보낸 폼 " + l));
        h.addAll(List.of("폼 수정", "바뀐 칸", "목표 거리(km)", "결과", "후보 수",
                "장소 찾기(ms)", "길찾기(ms)", "고르기(ms)", "찾기 합계(ms)"));
        for (int i = 1; i <= MAX_CANDIDATES; i++) {
            for (Object[] c : CANDIDATE_COLUMNS) {
                h.add("후보" + i + " " + c[0]);
            }
        }
        return h;
    }

    /**
     * 채우기 하나와 거기 이어진 코스 찾기 하나를 한 줄로. 둘 중 하나는 없을 수 있다(찾기 안 한 문장 · 직접 조건으로 찾은 요청).
     *
     * @param parsedAt · plannedAt 이미 한국 시각 문자열로 바꾼 값
     */
    static List<String> row(String parsedAt, String user, String sentence, JsonNode jev, JsonNode parsedForm, Integer parseMs,
                            String plannedAt, JsonNode sentForm, Integer targetMeters, Integer candidateCount, String reason,
                            Integer placeMs, Integer routeMs, Integer selectMs, JsonNode candidates) {
        List<String> row = new ArrayList<>(List.of(blank(parsedAt), blank(user), blank(sentence)));
        // Jev: 문장이 없으면(직접 조건) 칸을 비운다
        JsonNode answers = jev == null ? null : jev.get("answers");
        row.add(sentence == null ? "" : jev == null ? "실패(규칙만)" : "사용");
        row.add(percent(noul(answers, "on_topic")));
        row.add(choice(answers, "shape"));
        row.add(percent(choiceProbability(answers, "shape")));
        row.add(choice(answers, "start"));
        row.add(percent(choiceProbability(answers, "start")));
        row.add(jevPrefs(answers));

        List<String> parsed = form(parsedForm);
        row.addAll(parsed);
        row.add(number(parseMs));
        row.add(blank(plannedAt));
        List<String> sent = form(sentForm);
        row.addAll(sent);

        // 폼 수정: 둘 다 있을 때만 비교한다. 칸 단위로 바꾼 것을 "거리(km): 5 → 6"처럼 적는다
        List<String> changes = new ArrayList<>();
        if (parsedForm != null && sentForm != null) {
            for (int i = 0; i < FORM_LABELS.size(); i++) {
                if (!parsed.get(i).equals(sent.get(i))) {
                    changes.add("%s: %s → %s".formatted(FORM_LABELS.get(i), orNone(parsed.get(i)), orNone(sent.get(i))));
                }
            }
        }
        row.add(parsedForm == null || sentForm == null ? "" : changes.isEmpty() ? "아니오" : "예");
        row.add(String.join(" / ", changes));

        row.add(km(targetMeters == null ? null : targetMeters.doubleValue()));
        row.add(candidateCount == null ? "" : candidateCount > 0 ? "후보 있음" : REASON.getOrDefault(reason, blank(reason)));
        row.add(number(candidateCount));
        row.add(number(placeMs));
        row.add(number(routeMs));
        row.add(number(selectMs));
        row.add(placeMs == null ? "" : String.valueOf(placeMs + Objects.requireNonNullElse(routeMs, 0)
                + Objects.requireNonNullElse(selectMs, 0)));

        for (int i = 0; i < MAX_CANDIDATES; i++) {
            JsonNode c = candidates == null ? null : candidates.get(i);
            for (Object[] column : CANDIDATE_COLUMNS) {
                Double value = c == null ? null : numberOf(c, (String) column[1]);
                row.add((boolean) column[2] ? percent(value) : "distanceMeters".equals(column[1]) ? km(value) : plain(value));
            }
        }
        return row;
    }

    /** 폼을 FORM_LABELS 순서의 칸으로. 폼이 없으면 빈칸, 코스와 무관한 문장이면 출발 칸에 그렇게 적는다 */
    private static List<String> form(JsonNode f) {
        List<String> cells = new ArrayList<>(List.of("", "", "", "", "", ""));
        if (f == null) {
            return cells;
        }
        if (text(f, "message") != null) {
            cells.set(0, "코스와 무관한 문장");
            return cells;
        }
        JsonNode start = f.get("start");
        if (start != null && !start.isNull()) {
            cells.set(0, "PLACE".equals(text(start, "kind"))
                    ? Objects.requireNonNullElse(text(start, "query"), "장소(이름 못 읽음)") : "현재 위치");
        }
        // Map.of는 null 키로 찾으면 오류라 모양이 비었으면 먼저 거른다
        String shape = text(f, "shape");
        cells.set(1, shape == null ? "" : SHAPE.getOrDefault(shape, shape));
        cells.set(2, km(numberOf(f, "distanceM")));
        cells.set(3, plain(numberOf(f, "durationMin")));
        // 편도는 도착지, 경유는 경유지. 둘 다 없으면(한 바퀴 · 왕복) 빈칸
        String place = text(f, "endQuery");
        cells.set(4, blank(place != null ? place : text(f, "viaQuery")));
        JsonNode prefer = f.get("prefer");
        if (prefer != null && prefer.isArray()) {
            // 순서가 달라도 같은 조건이라 이름순으로 적는다(바뀐 칸 비교도 같아진다)
            cells.set(5, String.join(" · ", prefer.valueStream()
                    .map(p -> PREF.getOrDefault(p.asString().toLowerCase(), p.asString())).sorted().toList()));
        }
        return cells;
    }

    /** Jev가 50% 이상으로 본 원하는 길. 확률 높은 순: "평지 90% · 큰길 피하기 59%" */
    private static String jevPrefs(JsonNode answers) {
        if (answers == null) {
            return "";
        }
        return String.join(" · ", answers.propertyNames().stream()
                .filter(k -> k.startsWith("pref_"))
                .filter(k -> Objects.requireNonNullElse(noul(answers, k), 0.0) >= 0.5)
                .sorted(Comparator.comparing((String k) -> noul(answers, k)).reversed())
                .map(k -> PREF.getOrDefault(k.substring(5), k.substring(5)) + " " + percent(noul(answers, k)) + "%")
                .toList());
    }

    private static Double noul(JsonNode answers, String id) {
        return answers == null || answers.get(id) == null ? null : numberOf(answers.get(id), "noul");
    }

    private static String choice(JsonNode answers, String id) {
        String c = answers == null || answers.get(id) == null ? null : text(answers.get(id), "choice");
        return c == null ? "" : JEV_CHOICE.getOrDefault(c, c);
    }

    private static Double choiceProbability(JsonNode answers, String id) {
        JsonNode a = answers == null ? null : answers.get(id);
        String c = a == null ? null : text(a, "choice");
        return c == null || a.get("probabilities") == null ? null : numberOf(a.get("probabilities"), c);
    }

    private static String text(JsonNode node, String field) {
        JsonNode v = node.get(field);
        return v == null || v.isNull() ? null : v.asString();
    }

    private static Double numberOf(JsonNode node, String field) {
        JsonNode v = node.get(field);
        return v == null || !v.isNumber() ? null : v.asDouble();
    }

    /** 0.973 → "97.3" */
    private static String percent(Double ratio) {
        return ratio == null ? "" : plain(BigDecimal.valueOf(ratio * 100).setScale(1, RoundingMode.HALF_UP).doubleValue());
    }

    /** 4200 → "4.2" */
    private static String km(Double meters) {
        return meters == null ? "" : plain(meters / 1000);
    }

    /** 끝의 0을 뗀 숫자. 4.0 → "4" */
    private static String plain(Double value) {
        return value == null ? "" : BigDecimal.valueOf(value).stripTrailingZeros().toPlainString();
    }

    private static String number(Number value) {
        return value == null ? "" : value.toString();
    }

    private static String blank(String text) {
        return text == null ? "" : text;
    }

    private static String orNone(String text) {
        return text.isEmpty() ? "없음" : text;
    }
}

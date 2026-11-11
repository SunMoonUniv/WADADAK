package com.wadadak.course.internal.planner;

import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 문장 → 폼의 규칙 부분(B3 자동 생성 문장 입력). 숫자 · 장소 이름 · 분명한 단어만 읽고, 놓친 칸은 Jev가 보충한다({@link SentenceParser}).
 *
 * <p>시험 스크립트 {@code utilfile/_스크립트/course_planner/form_rules.py}를 옮겼다. 지명 사전 없이 패턴만 쓴다.
 * 시험에서 틀린 8개를 고쳤다: "선문대 정문"을 통째로, 문장 앞 · 가운데 지명, "공원 안에서"의 "에서"는 출발지가 아님,
 * "바퀴" · "거리"는 지명이 아님, "횡단보도"는 인도가 아님. "큰길 피해서"(Figma A7-1 예시)도 읽는다.
 */
final class SentenceRules {

    private SentenceRules() {
    }

    /** 못 읽은 칸은 null */
    record Numbers(Integer distanceM, Integer durationMin) {
    }

    /** 출발 · 도착 · 경유 장소 이름. 못 읽은 칸은 null */
    record Spans(String start, String end, String via) {
    }

    // ---- 숫자 ----

    private static final Map<Character, Integer> KO_DIGIT = Map.of(
            '일', 1, '이', 2, '삼', 3, '사', 4, '오', 5, '육', 6, '칠', 7, '팔', 8, '구', 9);
    private static final Pattern KM = Pattern.compile("(\\d+(?:\\.\\d+)?)\\s*(km|키로|킬로|k)(?![a-z])", Pattern.CASE_INSENSITIVE);
    private static final Pattern METER = Pattern.compile("(\\d+(?:\\.\\d+)?)\\s*(m|미터)(?![a-z])", Pattern.CASE_INSENSITIVE);
    private static final Pattern KO_KM = Pattern.compile("([일이삼사오육칠팔구십]+)\\s*(키로|킬로)");
    private static final Pattern FULL = Pattern.compile("풀\\s*코스|풀\\s*마라톤");
    private static final Pattern HOURS = Pattern.compile("(\\d+|한|두|세)\\s*시간(\\s*반)?");
    private static final Pattern MINUTES = Pattern.compile("(\\d+)\\s*분");

    static Numbers numbers(String text) {
        Integer distance = null;
        Matcher m;
        if ((m = KM.matcher(text)).find()) {
            distance = toInt(Double.parseDouble(m.group(1)) * 1000);
        } else if ((m = METER.matcher(text)).find()) {
            distance = toInt(Double.parseDouble(m.group(1)));
        } else if ((m = KO_KM.matcher(text)).find() && koNumber(m.group(1)) != null) {
            distance = koNumber(m.group(1)) * 1000;
        } else if (text.contains("하프")) {
            distance = 21_097;
        } else if (FULL.matcher(text).find()) {
            distance = 42_195;
        }
        Integer duration = null;
        if ((m = HOURS.matcher(text)).find()) {
            double hours = switch (m.group(1)) {
                case "한" -> 1;
                case "두" -> 2;
                case "세" -> 3;
                default -> Double.parseDouble(m.group(1));
            };
            duration = toInt(hours * 60 + (m.group(2) != null ? 30 : 0));
        } else if ((m = MINUTES.matcher(text)).find()) {
            duration = toInt(Double.parseDouble(m.group(1)));
        }
        return new Numbers(distance, duration);
    }

    /** "십오" 15, "이십" 20, "오" 5. 한글 숫자가 아니면 null */
    static Integer koNumber(String s) {
        if (s.isEmpty() || s.chars().anyMatch(ch -> ch != '십' && !KO_DIGIT.containsKey((char) ch))) {
            return null;
        }
        int ten = s.indexOf('십');
        if (ten < 0) {
            return s.length() == 1 ? KO_DIGIT.get(s.charAt(0)) : null;
        }
        return koDigit(s.substring(0, ten), 1) * 10 + koDigit(s.substring(ten + 1), 0);
    }

    private static int koDigit(String s, int otherwise) {
        return s.length() == 1 ? KO_DIGIT.getOrDefault(s.charAt(0), otherwise) : otherwise;
    }

    /** 아주 긴 숫자도 서버 오류 없이 받는다. 범위 검사는 생성 요청이 한다 */
    private static int toInt(double value) {
        return (int) Math.min(Integer.MAX_VALUE, Math.round(value));
    }

    // ---- 장소 이름 ----

    private static final String TOKEN = "[가-힣A-Za-z0-9]+";
    private static final Pattern TOKEN_P = Pattern.compile(TOKEN);
    private static final Set<String> NOT_PLACE = Set.of("여기", "집", "곳", "동네", "데", "안", "근처", "우리", "지금", "반환점", "중간",
            "길", "코스", "공원", "출발", "바퀴", "거리");
    private static final Set<String> NEAR = Set.of("근처", "앞", "부근", "주변", "쪽");
    /** "공원 안에서"처럼 장소 안을 말할 때의 "에서"는 출발지가 아니다 */
    private static final Set<String> INSIDE = Set.of("안", "속");
    /** "선문대 정문에서"는 앞 단어와 붙여 "선문대 정문"으로 읽는다 */
    private static final Set<String> GATE = Set.of("정문", "후문", "입구");
    private static final Pattern VERBISH = Pattern.compile(
            "(요|어|줘|자|해|다|게|로|고|서|와|래|꼬|싶어|추천|부탁해요|코스|km|키로|킬로)$");
    /** 문장 앞 · 가운데의 지명("수원 광교호수공원 둘레로", "광안대교 보면서"). 세 글자 이상만 본다(추천 · 하천 등 제외) */
    private static final Pattern PLACE_SUFFIX = Pattern.compile("(공원|호수|역|천|못|호|대교|산성|해수욕장|운동장|기념관|터미널)$");
    private static final Pattern DIGIT = Pattern.compile("\\d");
    private static final Pattern END = Pattern.compile("(" + TOKEN + ")까지");
    private static final Pattern VIA = Pattern.compile("(" + TOKEN + ")\\s*(찍고|들렀다|들러|거쳐)");
    private static final Pattern FROM = Pattern.compile("(" + TOKEN + ")\\s*에서");
    private static final Pattern DEPART = Pattern.compile("(" + TOKEN + ")\\s*출발");
    private static final Pattern FROM_EN = Pattern.compile("(?:from|near)\\s+([^,]+?)(?:,|$)", Pattern.CASE_INSENSITIVE);

    static Spans spans(String text) {
        Matcher m;
        String end = (m = END.matcher(text)).find() ? clean(m.group(1)) : null;
        String via = (m = VIA.matcher(text)).find() ? clean(m.group(1)) : null;

        String start = null;
        boolean saidFrom = false; // "…에서"가 있었다. 있으면 아래 추측은 하지 않는다
        m = FROM.matcher(text);
        while (m.find()) {
            String token = m.group(1);
            if (INSIDE.contains(token)) {
                continue;
            }
            saidFrom = true;
            List<String> before = tokens(text.substring(0, m.start()));
            String prev = before.isEmpty() ? null : before.getLast();
            if (NEAR.contains(token)) { // "천안역 근처에서"는 앞 단어
                token = prev;
            } else if (GATE.contains(token) && clean(prev) != null) {
                token = prev + " " + token;
            }
            if (clean(token) != null) {
                start = token;
                break;
            }
        }
        if (start != null || saidFrom) {
            return new Spans(start, end, via);
        }

        if ((m = DEPART.matcher(text)).find() || (m = FROM_EN.matcher(text)).find()) {
            start = clean(m.group(1).strip());
        }
        int comma = text.lastIndexOf(',');
        if (start == null && comma >= 0) { // "…, 천안 불당동"
            List<String> tail = words(text.substring(comma + 1)).stream().filter(w -> !NEAR.contains(w)).toList();
            if (!tail.isEmpty() && tail.size() <= 3 && tail.stream().noneMatch(w -> verbish(w) || hasDigit(w))) {
                start = clean(tail.getLast());
            }
        }
        if (start == null) { // 끝의 명사: "… 7km 일산 호수공원"
            List<String> words = words(text);
            List<String> tail = new ArrayList<>();
            for (String w : words.reversed()) {
                if (NEAR.contains(w)) {
                    continue;
                }
                if (verbish(w) || hasDigit(w) || NOT_PLACE.contains(w)) {
                    break;
                }
                tail.add(w);
            }
            if (!tail.isEmpty() && tail.size() < words.size()) {
                start = tail.getFirst();
            } else if (text.contains("왕복")) {
                List<String> head = words(text.substring(0, text.indexOf("왕복")));
                start = head.isEmpty() ? null : clean(head.getLast());
            }
        }
        if (start == null) {
            start = tokens(text).stream()
                    .filter(t -> t.length() >= 3 && PLACE_SUFFIX.matcher(t).find() && !verbish(t) && clean(t) != null)
                    .findFirst().orElse(null);
        }
        return new Spans(start, end, via);
    }

    private static String clean(String token) {
        return token != null && !token.isEmpty() && !NOT_PLACE.contains(token) && !hasDigit(token) ? token : null;
    }

    private static List<String> tokens(String text) {
        return TOKEN_P.matcher(text).results().map(r -> r.group()).toList();
    }

    private static List<String> words(String text) {
        String s = text.strip();
        return s.isEmpty() ? List.of() : List.of(s.split("\\s+"));
    }

    private static boolean verbish(String word) {
        return VERBISH.matcher(word).find();
    }

    private static boolean hasDigit(String s) {
        return DIGIT.matcher(s).find();
    }

    // ---- 분명한 단어 ----

    private static final Pattern ON_TOPIC = Pattern.compile(
            "코스|뛰|달리|달릴|러닝|조깅|한\\s*바퀴|왕복|편도|순환|루트|\\brun\\b|\\bloop\\b", Pattern.CASE_INSENSITIVE);

    /** 숫자나 달리기 단어가 있으면 코스 요청이다 */
    static boolean onTopicByKeyword(String text) {
        Numbers n = numbers(text);
        return n.distanceM() != null || n.durationMin() != null || ON_TOPIC.matcher(text).find();
    }

    private static final Pattern VIA_WORD = Pattern.compile("찍고|들렀다|들러|거쳐");
    private static final Pattern END_WORD = Pattern.compile("까지|편도");

    /** 모양 단어가 없으면 LOOP */
    static Shape keywordShape(String text) {
        if (VIA_WORD.matcher(text).find()) {
            return Shape.VIA;
        }
        if (text.contains("왕복")) {
            return Shape.OUT_AND_BACK;
        }
        if (END_WORD.matcher(text).find()) {
            return Shape.POINT_TO_POINT;
        }
        return Shape.LOOP;
    }

    /** 부정: "큰길은 피하고", "오르막 없는", "대로는 빼고" */
    private static final String NEG = "\\s*(?:은|는|이|가)?\\s*(?:없|말고|싫|피하|피해|빼|안\\s)";
    private static final Pattern HILL_NEG = Pattern.compile("(언덕|오르막|경사)" + NEG);
    private static final Pattern FLAT = Pattern.compile("평지|평탄|평평");
    private static final Pattern HILL = Pattern.compile("언덕|오르막|경사|\\bhill", Pattern.CASE_INSENSITIVE);
    private static final Pattern SIDEWALK = Pattern.compile("인도|(?<!횡단)보도|sidewalk", Pattern.CASE_INSENSITIVE);
    private static final Pattern ARTERIAL_NEG = Pattern.compile("(큰길|차도|대로|차\\s*다니는\\s*길|차\\s*다니는\\s*큰길)" + NEG);
    private static final Pattern ARTERIAL_EN = Pattern.compile("avoid big roads", Pattern.CASE_INSENSITIVE);
    private static final Pattern STORE = Pattern.compile("편의점|물\\s*사|마트|매점");
    private static final Pattern TOILET = Pattern.compile("화장실|toilet", Pattern.CASE_INSENSITIVE);
    private static final Pattern RIVER = Pattern.compile("(강|천|하천)\\s*(따라|변)|강변|river", Pattern.CASE_INSENSITIVE);
    private static final Pattern PARK = Pattern.compile("공원\\s*(안|위주|속)");
    private static final Pattern NO_RETRACE = Pattern.compile("반복\\s*없|같은\\s*길|두\\s*번\\s*안");

    static Set<Pref> keywordPrefs(String text) {
        Set<Pref> p = EnumSet.noneOf(Pref.class);
        boolean hillNeg = HILL_NEG.matcher(text).find();
        if (FLAT.matcher(text).find() || hillNeg) {
            p.add(Pref.FLAT);
        }
        if (HILL.matcher(text).find() && !hillNeg) {
            p.add(Pref.HILLY);
        }
        if (SIDEWALK.matcher(text).find()) {
            p.add(Pref.SIDEWALK);
        }
        if (ARTERIAL_NEG.matcher(text).find() || ARTERIAL_EN.matcher(text).find()) {
            p.add(Pref.AVOID_ARTERIAL);
        }
        if (STORE.matcher(text).find()) {
            p.add(Pref.STORE_ON_ROUTE);
        }
        if (TOILET.matcher(text).find()) {
            p.add(Pref.TOILET_ON_ROUTE);
        }
        if (RIVER.matcher(text).find()) {
            p.add(Pref.RIVER);
        }
        if (PARK.matcher(text).find()) {
            p.add(Pref.PARK);
        }
        if (NO_RETRACE.matcher(text).find()) {
            p.add(Pref.NO_RETRACE);
        }
        return p;
    }
}

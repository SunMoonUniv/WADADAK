package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.region.Region;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.region.RegionResolver;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.util.HtmlUtils;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

/**
 * 장소 이름 → 좌표(정책 B3 자동 생성, 개발 정책 1.2). NAVER API HUB(NCP) 지역 검색을 쓰고, 0건이면 NCP 지오코딩으로
 * 주소 · 동 이름을 찾는다. 서버만 부른다.
 *
 * <p>밖으로 가는 것은 검색어와 줄인 위치뿐이다: 지오코딩에는 소수 둘째 자리(약 1km)로 줄인 좌표, 지역 검색의 재검색에는
 * 시군구 이름(정책 B3-A06).
 *
 * <p>키가 없거나 상대가 실패하면(4xx · 5xx · 시간 초과) 그 호출은 0건으로 본다. 부르는 쪽은 장소를 못 찾은 것으로 다룬다.
 */
@Slf4j
@Component
class PlaceSearch {

    /** 지역 검색 결과가 모두 기준점에서 이보다 멀면(m) 시군구 이름을 붙여 한 번 더 찾는다. 지역 검색은 좌표 조건을 받지 않는다 */
    static final double FAR_METERS = 50_000;

    /** 지역 검색 분류에 이 말이 들어 있으면 가게다(검증 스크립트 naver_local_test.py의 BUSINESS) */
    private static final List<String> SHOP_CATEGORIES = List.of(
            "음식점", "카페", "술집", "한식", "중식", "일식", "양식", "분식", "제과", "숙박", "미용", "쇼핑", "생활,편의", "부동산");

    private final RestClient rest;
    private final Api search;
    private final Api geocode;
    private final RegionResolver regionResolver;
    private final RegionDirectory regionDirectory;

    @Autowired
    PlaceSearch(@Value("${app.course.planner.place.search.base-url}") String searchBaseUrl,
                @Value("${app.course.planner.place.search.client-id}") String searchClientId,
                @Value("${app.course.planner.place.search.client-secret}") String searchClientSecret,
                @Value("${app.course.planner.place.geocode.base-url}") String geocodeBaseUrl,
                @Value("${app.course.planner.place.geocode.client-id}") String geocodeClientId,
                @Value("${app.course.planner.place.geocode.client-secret}") String geocodeClientSecret,
                @Value("${app.course.planner.place.timeout}") Duration timeout,
                RegionResolver regionResolver, RegionDirectory regionDirectory) {
        this(RestClient.builder().requestFactory(timeouts(timeout)),
                new Api(searchBaseUrl, searchClientId, searchClientSecret),
                new Api(geocodeBaseUrl, geocodeClientId, geocodeClientSecret),
                regionResolver, regionDirectory);
    }

    /** 시험은 {@code MockRestServiceServer}를 붙인 builder를 넘긴다 */
    PlaceSearch(RestClient.Builder builder, Api search, Api geocode,
                RegionResolver regionResolver, RegionDirectory regionDirectory) {
        this.rest = builder.build();
        this.search = search;
        this.geocode = geocode;
        this.regionResolver = regionResolver;
        this.regionDirectory = regionDirectory;
    }

    /**
     * {@code query}로 찾은 장소들. 고르기는 {@link PlaceRules#pick}이 한다.
     *
     * @param near 기준점. 출발지는 현재 위치, 도착지 · 경유지는 출발지
     */
    List<PlaceHit> search(String query, GeoPoint near) {
        List<PlaceHit> hits = local(query);
        if (hits.isEmpty()) {
            return geocode(query, near);
        }
        if (hits.stream().allMatch(hit -> hit.location().distanceMeters(near) > FAR_METERS)) {
            // 먼 결과도 남긴다. "한강"처럼 정말 먼 곳이면 pick이 이름이 같은 먼 곳을 골라 tooFar로 알린다
            sigunguName(near).ifPresent(sigungu -> hits.addAll(local(sigungu + " " + query)));
        }
        return hits;
    }

    private List<PlaceHit> local(String query) {
        LocalResponse body = get(search, "/search/v1/local?query={query}&display=5", LocalResponse.class, query);
        List<PlaceHit> hits = new ArrayList<>();
        if (body == null || body.items() == null) {
            return hits;
        }
        for (LocalItem item : body.items()) {
            // mapx · mapy는 WGS84 경도 · 위도 × 1e7
            point(item.mapy(), item.mapx(), 1e7).ifPresent(location ->
                    hits.add(new PlaceHit(title(item.title()), location, isShop(item.category()))));
        }
        return hits;
    }

    private List<PlaceHit> geocode(String query, GeoPoint near) {
        String coordinate = String.format(Locale.ROOT, "%.2f,%.2f", near.lng(), near.lat());
        GeocodeResponse body = get(geocode, "/map-geocode/v2/geocode?query={query}&coordinate={coordinate}",
                GeocodeResponse.class, query, coordinate);
        List<PlaceHit> hits = new ArrayList<>();
        if (body == null || body.addresses() == null) {
            return hits;
        }
        for (Address address : body.addresses()) {
            String name = StringUtils.hasText(address.roadAddress()) ? address.roadAddress() : address.jibunAddress();
            point(address.y(), address.x(), 1).ifPresent(location -> hits.add(new PlaceHit(name, location, false)));
        }
        return hits;
    }

    /** 키가 없거나 실패하면 null */
    private <T> T get(Api api, String uri, Class<T> type, Object... uriVariables) {
        if (!StringUtils.hasText(api.clientId()) || !StringUtils.hasText(api.clientSecret())) {
            return null;
        }
        try {
            return rest.get().uri(api.baseUrl() + uri, uriVariables)
                    .header("X-NCP-APIGW-API-KEY-ID", api.clientId())
                    .header("X-NCP-APIGW-API-KEY", api.clientSecret())
                    .retrieve()
                    .body(type);
        } catch (RestClientException e) {
            // 요청 주소에 검색어 · 좌표가 들어 있어 예외 메시지는 남기지 않는다
            log.warn("장소 검색 실패: {} {}", uri.substring(0, uri.indexOf('?')),
                    e instanceof RestClientResponseException response ? response.getStatusCode() : e.getClass().getSimpleName());
            return null;
        }
    }

    private Optional<String> sigunguName(GeoPoint near) {
        return regionResolver.resolveCode(near.lat(), near.lng())
                .flatMap(code -> regionDirectory.findSigungu(code.substring(0, 5) + "00000"))
                .map(Region::name);
    }

    private static Optional<GeoPoint> point(String lat, String lng, double scale) {
        try {
            return Optional.of(new GeoPoint(Double.parseDouble(lat) / scale, Double.parseDouble(lng) / scale));
        } catch (RuntimeException e) { // 비었거나 숫자가 아니거나 좌표 범위 밖이면 그 결과만 버린다
            return Optional.empty();
        }
    }

    /** 검색어와 맞은 부분을 감싼 {@code <b>}를 지우고 HTML 엔티티({@code &amp;} 등)를 푼다 */
    private static String title(String title) {
        return HtmlUtils.htmlUnescape(title == null ? "" : title.replaceAll("</?b>", ""));
    }

    private static boolean isShop(String category) {
        return category != null && SHOP_CATEGORIES.stream().anyMatch(category::contains);
    }

    private static JdkClientHttpRequestFactory timeouts(Duration timeout) {
        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(
                HttpClient.newBuilder().connectTimeout(timeout).build());
        factory.setReadTimeout(timeout);
        return factory;
    }

    /** NCP API 하나의 주소와 앱 키 */
    record Api(String baseUrl, String clientId, String clientSecret) {
    }

    /** 지역 검색 응답 {@code {"items": [{"title": "<b>선문대</b>학교", "category": "교육,학문>대학교", "mapx": "1270749100", …}]}} */
    record LocalResponse(List<LocalItem> items) {
    }

    record LocalItem(String title, String category, String mapx, String mapy) {
    }

    /** 지오코딩 응답 {@code {"addresses": [{"roadAddress": …, "jibunAddress": …, "x": "127.07", "y": "36.79"}]}} */
    record GeocodeResponse(List<Address> addresses) {
    }

    record Address(String roadAddress, String jibunAddress, String x, String y) {
    }
}

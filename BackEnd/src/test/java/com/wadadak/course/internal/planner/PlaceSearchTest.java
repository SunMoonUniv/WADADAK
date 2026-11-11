package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.region.Region;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.region.RegionResolver;
import com.wadadak.course.internal.planner.PlaceSearch.Api;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.web.client.RequestMatcher;
import org.springframework.web.client.RestClient;

import java.net.SocketTimeoutException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.startsWith;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withException;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/** 장소 검색 응답 해석과 재검색 · 지오코딩 · 실패 처리. 실제 API는 부르지 않는다. */
class PlaceSearchTest {

    private static final GeoPoint SUNMOON = new GeoPoint(36.7983, 127.0746);
    private static final String LOCAL = "https://naverapihub.apigw.ntruss.com/search/v1/local?";
    private static final String GEOCODE = "https://maps.apigw.ntruss.com/map-geocode/v2/geocode?";
    private static final Api SEARCH_KEYS = new Api("https://naverapihub.apigw.ntruss.com", "search-id", "search-secret");
    private static final Api GEOCODE_KEYS = new Api("https://maps.apigw.ntruss.com", "geocode-id", "geocode-secret");

    private final RestClient.Builder builder = RestClient.builder();
    private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    private final RegionResolver regionResolver = mock(RegionResolver.class);
    private final RegionDirectory regionDirectory = mock(RegionDirectory.class);
    private final PlaceSearch placeSearch = new PlaceSearch(builder, SEARCH_KEYS, GEOCODE_KEYS, regionResolver, regionDirectory);

    @Test
    void readsLocalSearchResult() {
        server.expect(requestTo(startsWith(LOCAL)))
                .andExpect(method(HttpMethod.GET))
                .andExpect(query("query=선문대&display=5"))
                .andExpect(header("X-NCP-APIGW-API-KEY-ID", "search-id"))
                .andExpect(header("X-NCP-APIGW-API-KEY", "search-secret"))
                .andRespond(withSuccess("""
                        {"total": 2, "items": [
                          {"title": "<b>선문대</b>학교 아산캠퍼스", "category": "교육,학문>대학교",
                           "roadAddress": "충청남도 아산시 탕정면 선문로221번길 70", "mapx": "1270749100", "mapy": "367991500"},
                          {"title": "<b>선문대</b> 앞 &quot;밥&amp;술&quot;", "category": "술집>요리주점",
                           "mapx": "1270800000", "mapy": "368000000"},
                          {"title": "좌표 없는 곳", "category": "지명", "mapx": "", "mapy": ""}
                        ]}""", MediaType.APPLICATION_JSON));

        assertThat(placeSearch.search("선문대", SUNMOON)).containsExactly(
                new PlaceHit("선문대학교 아산캠퍼스", new GeoPoint(36.79915, 127.07491), false),
                new PlaceHit("선문대 앞 \"밥&술\"", new GeoPoint(36.8, 127.08), true));
        server.verify();
    }

    @Test
    void geocodesWhenLocalSearchFindsNothing() {
        server.expect(requestTo(startsWith(LOCAL)))
                .andRespond(withSuccess("""
                        {"total": 0, "items": []}""", MediaType.APPLICATION_JSON));
        // 좌표는 소수 둘째 자리(약 1km)로 줄여 보낸다
        server.expect(requestTo(startsWith(GEOCODE)))
                .andExpect(query("query=천안 신부동&coordinate=127.07,36.80"))
                .andExpect(header("X-NCP-APIGW-API-KEY-ID", "geocode-id"))
                .andExpect(header("X-NCP-APIGW-API-KEY", "geocode-secret"))
                .andRespond(withSuccess("""
                        {"status": "OK", "meta": {"totalCount": 1}, "addresses": [
                          {"roadAddress": "", "jibunAddress": "충청남도 천안시 동남구 신부동", "x": "127.1557", "y": "36.8188"}
                        ], "errorMessage": ""}""", MediaType.APPLICATION_JSON));

        assertThat(placeSearch.search("천안 신부동", SUNMOON)).containsExactly(
                new PlaceHit("충청남도 천안시 동남구 신부동", new GeoPoint(36.8188, 127.1557), false));
        server.verify();
    }

    @Test
    void searchesAgainWithSigunguWhenAllResultsAreFar() {
        given(regionResolver.resolveCode(SUNMOON.lat(), SUNMOON.lng())).willReturn(Optional.of("4420036000"));
        given(regionDirectory.findSigungu("4420000000")).willReturn(Optional.of(new Region("4420000000", "아산시", "충청남도 아산시")));
        server.expect(requestTo(startsWith(LOCAL)))
                .andExpect(query("query=온천천&display=5"))
                .andRespond(withSuccess("""
                        {"items": [{"title": "<b>온천천</b>", "category": "지명>하천", "mapx": "1290877700", "mapy": "351939300"}]}""",
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(startsWith(LOCAL)))
                .andExpect(query("query=아산시 온천천&display=5"))
                .andRespond(withSuccess("""
                        {"items": [{"title": "<b>온천천</b>", "category": "지명>하천", "mapx": "1269993700", "mapy": "367888600"}]}""",
                        MediaType.APPLICATION_JSON));

        assertThat(placeSearch.search("온천천", SUNMOON)).containsExactly(
                new PlaceHit("온천천", new GeoPoint(35.19393, 129.08777), false),
                new PlaceHit("온천천", new GeoPoint(36.78886, 126.99937), false));
        server.verify();
    }

    @Test
    void emptyWithoutKeys() {
        Api noKey = new Api("https://naverapihub.apigw.ntruss.com", "", "");
        PlaceSearch withoutKeys = new PlaceSearch(builder, noKey, noKey, regionResolver, regionDirectory);

        assertThat(withoutKeys.search("선문대", SUNMOON)).isEmpty();
        server.verify(); // 요청을 보내지 않았다
    }

    @Test
    void emptyOnServerErrorAndTimeout() {
        server.expect(requestTo(startsWith(LOCAL))).andRespond(withServerError());
        server.expect(requestTo(startsWith(GEOCODE))).andRespond(withException(new SocketTimeoutException("timeout")));

        assertThat(placeSearch.search("선문대", SUNMOON)).isEmpty();
        server.verify();
    }

    /** 쿼리 문자열을 풀어서 비교한다(한글 · 공백 · 쉼표는 인코딩돼 나간다) */
    private static RequestMatcher query(String expected) {
        return request -> assertThat(URLDecoder.decode(request.getURI().getRawQuery(), StandardCharsets.UTF_8))
                .isEqualTo(expected);
    }
}

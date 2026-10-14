package com.wadadak.common.storage;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.wait.strategy.Wait;

import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 실제 저장소(공용 서버와 같은 RustFS)에 앱처럼 폼으로 올려 본다. Docker가 필요하다.
 * 크기 · 형식 제한은 서명한 폼 조건을 저장소가 지켜야 하므로 저장소 쪽에서 막히는지 확인한다.
 */
class ObjectStorageTest {

    static final GenericContainer<?> rustfs = new GenericContainer<>("rustfs/rustfs:1.0.1")
            .withEnv("RUSTFS_ACCESS_KEY", "wadadak")
            .withEnv("RUSTFS_SECRET_KEY", "wadadak-test")
            .withExposedPorts(9000)
            .waitingFor(Wait.forHttp("/health").forStatusCode(200));

    static ObjectStorage storage;
    final HttpClient http = HttpClient.newHttpClient();

    @BeforeAll
    static void start() {
        rustfs.start();
        String endpoint = "http://" + rustfs.getHost() + ":" + rustfs.getMappedPort(9000);
        storage = new ObjectStorage(endpoint, endpoint + "/", "wadadak", "wadadak", "wadadak-test", Clock.systemUTC());
    }

    @AfterAll
    static void stop() {
        rustfs.stop();
    }

    @Test
    void uploadsWithFormAndServesPublicly() throws Exception {
        UploadForm form = storage.photoUploadForm("review");
        byte[] photo = "jpeg-bytes".getBytes(StandardCharsets.UTF_8);

        assertThat(form.key()).matches("review/[0-9a-f-]{36}\\.jpg");
        assertThat(post(form, "image/jpeg", photo).statusCode()).isBetween(200, 299);
        assertThat(storage.isUploadedPhoto("review", form.key())).isTrue();
        // 다른 모듈 키로는 쓸 수 없다
        assertThat(storage.isUploadedPhoto("member", form.key())).isFalse();

        // 로그인 없이 받는다. 버킷 목록은 막는다.
        HttpResponse<byte[]> download = http.send(HttpRequest.newBuilder(URI.create(storage.url(form.key()))).build(),
                HttpResponse.BodyHandlers.ofByteArray());
        assertThat(download.statusCode()).isEqualTo(200);
        assertThat(download.body()).isEqualTo(photo);
        assertThat(http.send(HttpRequest.newBuilder(URI.create(form.url())).build(), HttpResponse.BodyHandlers.discarding())
                .statusCode()).isEqualTo(403);

        storage.deleteAfterCommit(List.of(form.key()));
        assertThat(storage.isUploadedPhoto("review", form.key())).isFalse();
    }

    @Test
    void rejectsOtherTypeOrOversizedFile() throws Exception {
        UploadForm png = storage.photoUploadForm("review");
        // 서명한 조건에 어긋나면 거부한다(AWS는 403, RustFS는 400)
        assertThat(post(png, "image/png", new byte[10]).statusCode()).isBetween(400, 499);
        assertThat(storage.isUploadedPhoto("review", png.key())).isFalse();

        UploadForm small = storage.photoUploadForm("review", 5);
        assertThat(post(small, "image/jpeg", new byte[6]).statusCode()).isBetween(400, 499);
        assertThat(storage.isUploadedPhoto("review", small.key())).isFalse();
    }

    @Test
    void unknownOrMalformedKeysAreNotUploaded() {
        assertThat(storage.isUploadedPhoto("review", "review/" + UUID.randomUUID() + ".jpg")).isFalse();
        assertThat(storage.isUploadedPhoto("review", "review/../member/x.jpg")).isFalse();
        assertThat(storage.isUploadedPhoto("review", "review/photo.png")).isFalse();
    }

    /** 앱과 같은 multipart 폼. 파일은 마지막 필드여야 한다. */
    private HttpResponse<String> post(UploadForm form, String contentType, byte[] file) throws Exception {
        String boundary = "wadadak" + UUID.randomUUID();
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        for (Map.Entry<String, String> field : form.fields().entrySet()) {
            String value = field.getKey().equals("Content-Type") ? contentType : field.getValue();
            body.writeBytes(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"" + field.getKey() + "\"\r\n\r\n"
                    + value + "\r\n").getBytes(StandardCharsets.UTF_8));
        }
        body.writeBytes(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n"
                + "Content-Type: " + contentType + "\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        body.writeBytes(file);
        body.writeBytes(("\r\n--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8));
        return http.send(HttpRequest.newBuilder(URI.create(form.url()))
                        .header("Content-Type", "multipart/form-data; boundary=" + boundary)
                        .POST(HttpRequest.BodyPublishers.ofByteArray(body.toByteArray())).build(),
                HttpResponse.BodyHandlers.ofString());
    }
}

package com.wadadak.common.storage;

import com.wadadak.common.entity.UuidV7;
import io.minio.BucketExistsArgs;
import io.minio.MakeBucketArgs;
import io.minio.MinioClient;
import io.minio.PostPolicy;
import io.minio.RemoveObjectArgs;
import io.minio.SetBucketPolicyArgs;
import io.minio.StatObjectArgs;
import io.minio.errors.ErrorResponseException;
import io.minio.errors.MinioException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Clock;
import java.time.Duration;
import java.time.ZonedDateTime;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * 사진 저장소(S3 호환, 개발 정책 7장 사진 업로드). 앱이 업로드 폼으로 직접 올리고, 모듈은 키만 저장한다.
 * 키는 {@code {module}/{UUID}.jpg}다. 사진은 공개 읽기라 {@link #url} 주소로 누구나 받는다(리뷰·프로필 사진은 모두에게 보인다).
 * 로컬은 {@code BackEnd/compose.yaml}, 공용 서버는 {@code deploy/compose.yaml}의 RustFS다.
 */
@Slf4j
@Component
public class ObjectStorage {

    /** 사진 한 장 크기 한도(정책 공통 5) */
    static final long MAX_PHOTO_BYTES = 50L * 1024 * 1024;
    private static final Duration FORM_TTL = Duration.ofMinutes(10);
    private static final String JPEG = "image/jpeg";
    private static final Pattern KEY = Pattern.compile("[a-z]+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.jpg");
    private static final Set<String> MISSING = Set.of("NoSuchKey", "NoSuchBucket", "NoSuchObject");

    private final MinioClient client;
    private final String bucket;
    private final String publicUrl;
    private final Clock clock;
    private volatile boolean bucketReady;

    ObjectStorage(@Value("${app.common.storage.endpoint}") String endpoint,
                  @Value("${app.common.storage.public-url}") String publicUrl,
                  @Value("${app.common.storage.bucket}") String bucket,
                  @Value("${app.common.storage.access-key}") String accessKey,
                  @Value("${app.common.storage.secret-key}") String secretKey,
                  Clock clock) {
        // 리전을 정해 두면 폼 서명에 저장소를 부르지 않는다. 저장소가 꺼져 있어도 서버는 뜬다.
        this.client = MinioClient.builder().endpoint(endpoint).region("us-east-1").credentials(accessKey, secretKey).build();
        this.publicUrl = publicUrl.replaceAll("/+$", "");
        this.bucket = bucket;
        this.clock = clock;
    }

    /** 사진 한 장을 올릴 폼. 키는 서버가 정한다. JPEG만, 50MB 이하, 10분 안에 올린다. */
    public UploadForm photoUploadForm(String module) {
        return photoUploadForm(module, MAX_PHOTO_BYTES);
    }

    UploadForm photoUploadForm(String module, long maxBytes) {
        ensureBucket();
        String key = module + "/" + UuidV7.create() + ".jpg";
        PostPolicy policy = new PostPolicy(bucket, ZonedDateTime.now(clock).plus(FORM_TTL));
        policy.addEqualsCondition("key", key);
        policy.addEqualsCondition("Content-Type", JPEG);
        policy.addContentLengthRangeCondition(1L, maxBytes);
        Map<String, String> fields = new LinkedHashMap<>();
        fields.put("key", key);
        fields.put("Content-Type", JPEG);
        try {
            fields.putAll(client.getPresignedPostFormData(policy));
        } catch (MinioException e) {
            throw new IllegalStateException("업로드 폼을 만들지 못했습니다.", e);
        }
        return new UploadForm(publicUrl + "/" + bucket, key, fields);
    }

    /** {@code module}의 사진 키 형식이고 실제로 올라와 있다. */
    public boolean isUploadedPhoto(String module, String key) {
        if (!KEY.matcher(key).matches() || !key.startsWith(module + "/")) {
            return false;
        }
        try {
            client.statObject(StatObjectArgs.builder().bucket(bucket).object(key).build());
            return true;
        } catch (ErrorResponseException e) {
            if (MISSING.contains(e.errorResponse().code())) {
                return false;
            }
            throw new IllegalStateException("사진을 확인하지 못했습니다.", e);
        } catch (MinioException e) {
            throw new IllegalStateException("사진을 확인하지 못했습니다.", e);
        }
    }

    /** 앱이 사진을 받는 주소 */
    public String url(String key) {
        return publicUrl + "/" + bucket + "/" + key;
    }

    /** 트랜잭션이 커밋된 뒤 지운다(롤백되면 그대로 둔다). 트랜잭션 밖이면 바로 지운다. */
    public void deleteAfterCommit(Collection<String> keys) {
        if (keys.isEmpty()) {
            return;
        }
        List<String> targets = List.copyOf(keys);
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            delete(targets);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                delete(targets);
            }
        });
    }

    // ponytail: 지우지 못한 파일, 폼만 받고 저장하지 않은 파일은 남는다. 저장소가 차면 정리 배치를 둔다.
    private void delete(List<String> keys) {
        for (String key : keys) {
            try {
                client.removeObject(RemoveObjectArgs.builder().bucket(bucket).object(key).build());
            } catch (MinioException e) {
                log.warn("사진을 지우지 못했습니다: {}", key, e);
            }
        }
    }

    /** 처음 올릴 때 버킷을 만들고 공개 읽기(GetObject만, 목록은 막음)를 건다. */
    private synchronized void ensureBucket() {
        if (bucketReady) {
            return;
        }
        try {
            if (!client.bucketExists(BucketExistsArgs.builder().bucket(bucket).build())) {
                client.makeBucket(MakeBucketArgs.builder().bucket(bucket).build());
            }
            client.setBucketPolicy(SetBucketPolicyArgs.builder().bucket(bucket).config("""
                    {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Principal": {"AWS": ["*"]},
                      "Action": ["s3:GetObject"], "Resource": ["arn:aws:s3:::%s/*"]}]}""".formatted(bucket)).build());
        } catch (MinioException e) {
            throw new IllegalStateException("저장소 버킷을 준비하지 못했습니다.", e);
        }
        bucketReady = true;
    }
}

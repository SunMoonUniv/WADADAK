package com.wadadak.common.storage;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.IllegalTransactionStateException;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

/**
 * 폼 장부를 실제 DB로 확인한다. 저장소는 흉내만 낸다(실제 업로드는 ObjectStorageTest). Docker가 필요하다.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class PhotoUploadsTest {

    @Autowired
    PhotoUploads uploads;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    PlatformTransactionManager transactionManager;

    @MockitoBean
    ObjectStorage storage;

    @BeforeEach
    void storage() {
        given(storage.photoUploadForm(anyString())).willAnswer(call ->
                new UploadForm("https://files.test/wadadak", call.getArgument(0) + "/" + UUID.randomUUID() + ".jpg", Map.of()));
        given(storage.isUploadedPhoto(anyString(), anyString())).willReturn(true);
        given(storage.remove(anyString())).willReturn(true);
    }

    @Test
    void limitsUnsavedFormsPerOwner() {
        String owner = UUID.randomUUID().toString();
        List<String> keys = new ArrayList<>();
        for (int i = 0; i < PhotoUploads.MAX_PENDING; i++) {
            keys.add(uploads.form("review", owner).key());
        }

        assertThatThrownBy(() -> uploads.form("review", owner))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CommonErrorCode.TOO_MANY_PHOTO_UPLOADS));
        // 다른 사람은 따로 센다
        assertThat(uploads.form("review", UUID.randomUUID().toString()).key()).startsWith("review/");

        // 저장한 폼은 세지 않는다. 정상 사용은 받자마자 저장하므로 한도에 닿지 않는다
        assertThat(claim("review", owner, keys.getFirst())).isTrue();
        uploads.form("review", owner);
        assertThatThrownBy(() -> uploads.form("review", owner)).isInstanceOf(AppException.class);

        // 1시간이 지난 폼은 세지 않는다
        jdbc.update("UPDATE common.photo_uploads SET created_at = created_at - interval '2 hours' WHERE owner = ?", owner);
        assertThat(uploads.form("review", owner).key()).startsWith("review/");
    }

    @Test
    void onlyFormOwnerClaimsOnce() {
        String owner = UUID.randomUUID().toString();
        String key = uploads.form("review", owner).key();

        assertThat(claim("review", UUID.randomUUID().toString(), key)).isFalse();
        assertThat(claim("review", owner, "review/" + UUID.randomUUID() + ".jpg")).isFalse();
        assertThat(claim("review", owner, key)).isTrue();
        assertThat(claim("review", owner, key)).isFalse();

        // 저장하는 쪽 트랜잭션 밖에서는 부를 수 없다(실패해도 장부가 돌아오지 않는다)
        assertThatThrownBy(() -> uploads.claim("review", owner, List.of(key))).isInstanceOf(IllegalTransactionStateException.class);
    }

    @Test
    void failedSaveLeavesPhotoForCleanup() {
        String owner = UUID.randomUUID().toString();
        String key = uploads.form("review", owner).key();
        given(storage.isUploadedPhoto("review", key)).willReturn(false);

        // 올라오지 않았으면 저장이 롤백되고 장부는 그대로다
        assertThat(claim("review", owner, key)).isFalse();
        assertThat(pending(key)).isTrue();
    }

    @Test
    void deletesAbandonedPhotos() {
        String owner = UUID.randomUUID().toString();
        String abandoned = uploads.form("review", owner).key();
        String failing = uploads.form("review", owner).key();
        String recent = uploads.form("review", owner).key();
        jdbc.update("UPDATE common.photo_uploads SET created_at = created_at - interval '2 hours' WHERE photo_key IN (?, ?)",
                abandoned, failing);
        given(storage.remove(failing)).willReturn(false);

        uploads.deleteAbandoned();

        verify(storage).remove(abandoned);
        verify(storage, never()).remove(recent);
        assertThat(pending(abandoned)).isFalse();
        assertThat(pending(recent)).isTrue();
        // 저장소가 안 되면 장부에 남겨 다음에 다시 지운다
        assertThat(pending(failing)).isTrue();
    }

    /** 저장하는 쪽처럼 트랜잭션 안에서 claim하고, 실패하면 롤백한다 */
    private boolean claim(String module, String owner, String key) {
        return new TransactionTemplate(transactionManager).execute(status -> {
            boolean claimed = uploads.claim(module, owner, List.of(key));
            if (!claimed) {
                status.setRollbackOnly();
            }
            return claimed;
        });
    }

    private boolean pending(String key) {
        return jdbc.queryForObject("SELECT count(*) FROM common.photo_uploads WHERE photo_key = ?", Integer.class, key) > 0;
    }
}

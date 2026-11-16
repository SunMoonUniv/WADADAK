package com.wadadak.common.storage;

import java.util.Map;

/**
 * 사진 한 장을 저장소에 직접 올리는 폼(S3 Presigned POST).
 * 앱은 {@code url}에 multipart/form-data로 {@code fields}를 모두 넣고 파일을 마지막 {@code file} 필드로 붙여 POST한다.
 *
 * @param key    올린 뒤 리뷰·프로필 저장 요청에 담는 키
 * @param fields 그대로 보내는 폼 필드(key · Content-Type · 서명)
 */
public record UploadForm(String url, String key, Map<String, String> fields) {
}

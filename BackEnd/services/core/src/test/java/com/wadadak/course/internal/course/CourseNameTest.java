package com.wadadak.course.internal.course;

import com.wadadak.common.exception.AppException;
import org.junit.jupiter.api.Test;

import java.text.Normalizer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CourseNameTest {

    @Test
    void displayTrimsAndCollapsesSpaces() {
        assertThat(CourseName.display("  한강   러닝\t코스 ")).isEqualTo("한강 러닝 코스");
    }

    @Test
    void keyIgnoresAllSpacesAndCase() {
        assertThat(CourseName.key("한강 러닝")).isEqualTo("한강러닝");
        assertThat(CourseName.key("한 강 러 닝")).isEqualTo("한강러닝");
        assertThat(CourseName.key("River Run")).isEqualTo("riverrun");
        assertThat(CourseName.key("한강 러닝중")).isNotEqualTo(CourseName.key("한강러닝"));
        assertThat(CourseName.key("한강 러닝코스")).isNotEqualTo(CourseName.key("한강러닝"));
    }

    @Test
    void requireValidChecksLengthAfterTrimming() {
        assertThat(CourseName.requireValid("  한강  러닝 ")).isEqualTo("한강 러닝");
        assertThat(CourseName.requireValid("한강")).isEqualTo("한강");
        assertThat(CourseName.requireValid("가".repeat(50))).hasSize(50);
        assertThatThrownBy(() -> CourseName.requireValid(" 한 ")).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> CourseName.requireValid("   ")).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> CourseName.requireValid("가".repeat(51))).isInstanceOf(AppException.class);
    }

    @Test
    void emojiCountsAsOneCharacter() {
        // 🏃는 UTF-16으로 2칸이지만 DB VARCHAR와 같이 1자로 센다
        assertThat(CourseName.requireValid("🏃".repeat(50))).isNotBlank();
        assertThatThrownBy(() -> CourseName.requireValid("🏃".repeat(51))).isInstanceOf(AppException.class);
    }

    @Test
    void decomposedHangulIsSameName() {
        String decomposed = Normalizer.normalize("한강러닝", Normalizer.Form.NFD);

        assertThat(decomposed).isNotEqualTo("한강러닝");
        assertThat(CourseName.key(decomposed)).isEqualTo(CourseName.key("한강러닝"));
        assertThat(CourseName.display(decomposed)).isEqualTo("한강러닝");
    }
}

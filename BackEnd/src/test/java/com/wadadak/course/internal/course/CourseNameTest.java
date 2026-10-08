package com.wadadak.course.internal.course;

import org.junit.jupiter.api.Test;

import java.text.Normalizer;

import static org.assertj.core.api.Assertions.assertThat;

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
    void decomposedHangulIsSameName() {
        String decomposed = Normalizer.normalize("한강러닝", Normalizer.Form.NFD);

        assertThat(decomposed).isNotEqualTo("한강러닝");
        assertThat(CourseName.key(decomposed)).isEqualTo(CourseName.key("한강러닝"));
        assertThat(CourseName.display(decomposed)).isEqualTo("한강러닝");
    }
}

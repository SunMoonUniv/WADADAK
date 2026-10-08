package com.wadadak.course.internal.course;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.UUID;

public interface CourseRepository extends JpaRepository<Course, UUID> {

    /** 활성 코스 중 같은 이름(대소문자 무시)이 있는지. DB 부분 유니크 인덱스 {@code courses_name_uk}와 같은 기준이다. */
    @Query("SELECT count(c) > 0 FROM Course c WHERE lower(c.name) = lower(:name) AND c.status = com.wadadak.event.course.CourseStatus.ACTIVE")
    boolean existsActiveByName(String name);
}

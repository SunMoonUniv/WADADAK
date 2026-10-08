package com.wadadak.course.internal.course;

import com.wadadak.event.course.CourseStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface CourseRepository extends JpaRepository<Course, UUID> {

    boolean existsByNameKeyAndStatus(String nameKey, CourseStatus status);

    /** 활성 코스 중 같은 이름이 있는지. 공백·대소문자는 무시한다({@link CourseName#key(String)}). */
    default boolean existsActiveByName(String name) {
        return existsByNameKeyAndStatus(CourseName.key(name), CourseStatus.ACTIVE);
    }
}

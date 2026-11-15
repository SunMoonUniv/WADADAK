package com.wadadak.course.internal.registration;

import com.wadadak.common.response.ApiResult;
import com.wadadak.course.internal.course.CourseName;
import com.wadadak.course.internal.course.CourseRepository;
import io.swagger.v3.oas.annotations.Operation;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/courses/name-availability")
@RequiredArgsConstructor
class CourseNameController {

    private final CourseRepository courseRepository;

    @Operation(summary = "코스 이름 확인 (B4-02 · B7)",
            description = "2~50자인지, 활성 코스 중 같은 이름이 있는지 확인한다. 공백·대소문자만 다른 이름도 같은 이름이다. "
                    + "B7 코스 수정에서는 courseId를 함께 보내면 그 코스의 지금 이름은 빼고 본다. "
                    + "길이 밖이면 COMMON-001. 중복은 에러가 아니라 available=false. 등록 · 수정 때 다시 확인한다(중복이면 COURSE-006).")
    @GetMapping
    ApiResult<NameAvailability> check(@RequestParam String name, @RequestParam(required = false) UUID courseId) {
        String display = CourseName.requireValid(name);
        boolean taken = courseId == null ? courseRepository.existsActiveByName(display)
                : courseRepository.existsActiveByNameExcept(display, courseId);
        return ApiResult.success(new NameAvailability(display, !taken));
    }
}

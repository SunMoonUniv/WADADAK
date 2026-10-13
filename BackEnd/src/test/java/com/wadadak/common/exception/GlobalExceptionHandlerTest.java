package com.wadadak.common.exception;

import org.apache.tomcat.util.http.InvalidParameterException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import static org.assertj.core.api.Assertions.assertThat;

class GlobalExceptionHandlerTest {

    /** Tomcat은 쿼리 값을 UTF-8로 풀지 못하면 컨트롤러가 값을 읽을 때 InvalidParameterException을 던진다. */
    @RestController
    static class UndecodableParameterController {

        @GetMapping("/undecodable")
        String undecodable() {
            throw new InvalidParameterException("Character decoding failed. Parameter [query] has been ignored.");
        }
    }

    private final MockMvcTester mvc = MockMvcTester.create(MockMvcBuilders
            .standaloneSetup(new UndecodableParameterController())
            .setControllerAdvice(new GlobalExceptionHandler())
            .build());

    @Test
    void undecodableParameterIsBadRequestNotServerError() {
        assertThat(mvc.get().uri("/undecodable"))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }
}

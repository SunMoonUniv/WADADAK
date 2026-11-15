package com.wadadak.common.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ViewControllerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * 운영자 웹(static/admin/index.html)을 {@code /admin} 주소로 연다. 스프링은 루트(/)가 아닌 폴더 주소에서 index.html을 찾아 주지 않는다.
 */
@Configuration
class AdminWebConfig implements WebMvcConfigurer {

    @Override
    public void addViewControllers(ViewControllerRegistry registry) {
        registry.addRedirectViewController("/admin", "/admin/");
        registry.addViewController("/admin/").setViewName("forward:/admin/index.html");
    }
}

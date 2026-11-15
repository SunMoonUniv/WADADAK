package com.wadadak;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.modulith.Modulithic;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

@Modulithic(sharedModules = "common")
@SpringBootApplication
public class WadadakApplication {

    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(WadadakApplication.class);
        // 저장소 루트를 작업 폴더로 띄워도(IntelliJ 기본값) BackEnd/.local의 로컬 키를 찾는다.
        if (Files.isDirectory(Path.of("BackEnd", ".local"))) {
            app.setDefaultProperties(Map.of("app.local-dir", "BackEnd/.local"));
        }
        app.run(args);
    }

}

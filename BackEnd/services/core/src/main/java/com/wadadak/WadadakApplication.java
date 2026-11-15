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
        // 저장소 루트나 services/core를 작업 폴더로 띄워도(IntelliJ) BackEnd/.local의 로컬 키를 찾는다.
        // gradlew bootRun은 BackEnd에서 띄운다(build.gradle).
        for (String dir : new String[]{"BackEnd/.local", "../../.local"}) {
            if (Files.isDirectory(Path.of(dir))) {
                app.setDefaultProperties(Map.of("app.local-dir", dir));
                break;
            }
        }
        app.run(args);
    }

}

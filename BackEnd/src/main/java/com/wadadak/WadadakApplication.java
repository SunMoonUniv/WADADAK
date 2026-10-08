package com.wadadak;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.modulith.Modulithic;

@Modulithic(sharedModules = "common")
@SpringBootApplication
public class WadadakApplication {

    public static void main(String[] args) {
        SpringApplication.run(WadadakApplication.class, args);
    }

}

import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play 업로드 키. android/key.properties(커밋 금지)에 storeFile·storePassword·keyAlias·keyPassword.
val uploadKey = Properties().apply {
    rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}

android {
    namespace = "com.wadadak.wadadak"
    // permission_handler 13이 37 이상을 요구한다. targetSdk는 그대로라 실행 동작은 바뀌지 않는다.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 확정. 카카오·Google 콘솔에 이 ID로 등록했다(스토어 출시 후에는 바꿀 수 없다).
        applicationId = "com.wadadak.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            // 팀 공용 디버그 키. 저장소가 공개라 커밋하지 않고(.gitignore의 *.keystore) 팀 내부로만 나눈다.
            // 이 파일이 있으면 모든 PC의 키 해시가 같아 카카오·Google 콘솔에 하나만 등록하면 된다.
            // 없으면 각자 PC의 기본 디버그 키로 서명되고, 그 PC에서는 카카오 로그인이 실패한다.
            val shared = file("debug.keystore")
            if (shared.exists()) {
                storeFile = shared
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
        if (!uploadKey.isEmpty) {
            create("release") {
                storeFile = rootProject.file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            if (providers.gradleProperty("wearSmoke").orNull == "true") {
                applicationIdSuffix = ".wearsmoke"
            }
        }
        release {
            // key.properties가 없으면 디버그 키로 서명한다(`flutter run --release`용). Play는 이 번들을 거부한다.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
}

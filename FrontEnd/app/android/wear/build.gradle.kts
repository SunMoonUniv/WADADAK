import com.android.build.api.artifact.SingleArtifact.APK
import com.android.build.api.dsl.ApplicationExtension
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val phoneConfig = project(":app").extensions.getByType<ApplicationExtension>().defaultConfig

// 폰 앱과 같은 Play 업로드 키(android/key.properties).
val uploadKey = Properties().apply {
    rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}

android {
    namespace = "com.wadadak.wear"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.wadadak.app"
        minSdk = 30
        targetSdk = 36
        // Play는 한 앱(같은 applicationId) 안에서 버전 코드를 다시 쓸 수 없다. 워치는 폰 + 1억.
        versionCode = phoneConfig.versionCode?.plus(100_000_000)
        versionName = phoneConfig.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        getByName("debug") {
            // The Data Layer requires the phone and watch APKs to use the same key.
            val shared = rootProject.file("app/debug.keystore")
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
            // 폰과 같은 키여야 Data Layer가 붙는다. key.properties가 없으면 디버그 키.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    implementation("androidx.health:health-services-client:1.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
}

if (providers.environmentVariable("WADADAK_UPDATE_WEAR").orNull == "1") {
    val adb = androidComponents.sdkComponents.adb.get().asFile.absolutePath
    val transportLine = Regex("""^\S+\s+device\s+.*\btransport_id:(\d+)\b""")
    val transports = adbOutput(adb, "devices", "-l").orEmpty().lineSequence()
        .mapNotNull { transportLine.find(it)?.groupValues?.get(1) }
    val watches = transports.mapNotNull { transport ->
        val device = adbOutput(
            adb, "-t", transport, "shell",
            "pm has-feature android.hardware.type.watch; getprop ro.serialno",
        )?.lineSequence()?.map(String::trim)?.toList().orEmpty()
        if (device.firstOrNull() != "true") return@mapNotNull null
        val serial = device.getOrNull(1)?.takeIf(String::isNotEmpty)
        (serial ?: "transport:$transport") to transport
    }.distinctBy { it.first }.toList()

    val watch = watches.singleOrNull()
    if (watch == null) {
        logger.quiet(
            if (watches.isEmpty()) "WADADAK Wear: no connected watch. Skipping update."
            else "WADADAK Wear: multiple watches connected. Skipping update.",
        )
    } else {
        androidComponents.onVariants(androidComponents.selector().withBuildType("debug")) { variant ->
            val apkDirectory = variant.artifacts.get(APK)
            val loader = variant.artifacts.getBuiltArtifactsLoader()
            val updateWatch = tasks.register<Exec>("updateConnectedWearDebug") {
                dependsOn(":app:packageDebug")
                inputs.dir(apkDirectory)
                commandLine(adb, "-t", watch.second, "install", "-r")
                argumentProviders.add(CommandLineArgumentProvider {
                    val apk = loader.load(apkDirectory.get())?.elements?.singleOrNull()
                        ?: throw GradleException("Expected exactly one Wear OS APK.")
                    listOf(apk.outputFile)
                })
                isIgnoreExitValue = true
                doLast {
                    if (executionResult.get().exitValue == 0) {
                        logger.quiet("WADADAK Wear: watch app updated.")
                    } else {
                        logger.quiet("WADADAK Wear: update failed. Continuing with the phone app.")
                    }
                }
            }
            project(":app").tasks.named("assembleDebug") {
                dependsOn(updateWatch)
            }
        }
    }
}

fun Project.adbOutput(adb: String, vararg args: String): String? = runCatching {
    val result = providers.exec {
        commandLine(adb, *args)
        isIgnoreExitValue = true
    }
    result.standardOutput.asText.get().takeIf { result.result.get().exitValue == 0 }
}.getOrNull()

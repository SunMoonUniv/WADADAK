import com.android.build.api.artifact.SingleArtifact.APK
import com.android.build.api.dsl.ApplicationExtension

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val phoneConfig = project(":app").extensions.getByType<ApplicationExtension>().defaultConfig

android {
    namespace = "com.wadadak.wear"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.wadadak.app"
        minSdk = 30
        targetSdk = 36
        versionCode = phoneConfig.versionCode
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
    }

    buildTypes {
        debug {
            if (providers.gradleProperty("wearSmoke").orNull == "true") {
                applicationIdSuffix = ".wearsmoke"
            }
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

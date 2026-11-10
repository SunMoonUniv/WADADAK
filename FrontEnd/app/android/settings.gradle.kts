pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app", ":wear")

// Flutter invokes assembleDebug from the root. Add the watch only through the phone build hook.
if (providers.environmentVariable("WADADAK_UPDATE_WEAR").orNull == "1") {
    gradle.startParameter.setTaskNames(
        gradle.startParameter.taskNames.map { if (it == "assembleDebug") ":app:assembleDebug" else it },
    )
}

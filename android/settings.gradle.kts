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
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")

// Optional Unity runtime module (flutter_unity_widget).
// Wird nur eingebunden, wenn ein Unity-Android-Export vorhanden ist.
val unityExportAndroidDir = file("../unity_export/android")
val unityLibraryDir = file("../unity_export/android/unityLibrary")
if (unityExportAndroidDir.exists() && unityLibraryDir.exists()) {
    include(":unityLibrary")
    project(":unityLibrary").projectDir = unityLibraryDir
}

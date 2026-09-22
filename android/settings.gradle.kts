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
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

// Unity AR player, exported as an Android Library (.aar) and dropped in at
// android/unityLibrary (see its README.txt). Only included once that export
// actually exists — i.e. it has its own build.gradle(.kts) — otherwise this
// is a no-op so `flutter build` / `flutter run` keep working with no Unity
// module. Confirmed via a real build spike: unconditionally including an
// empty placeholder directory here fails the whole app build with "No
// matching variant of project :unityLibrary was found — No variants exist."
val unityLibraryDir = File(rootDir, "unityLibrary")
if (File(unityLibraryDir, "build.gradle").exists() ||
    File(unityLibraryDir, "build.gradle.kts").exists()
) {
    include(":unityLibrary")
    project(":unityLibrary").projectDir = unityLibraryDir
}

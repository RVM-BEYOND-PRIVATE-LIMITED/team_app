import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (team_app #50, item 9). The key is read from
// android/key.properties, which git ignores, as do keystore files: see
// "Release signing" in rvm_team_app/README.md. Debug and profile builds keep the
// debug key and never read this file; a release build without it stops with
// the message below instead of producing an app signed with the wrong key.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.isFile) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")

/** Why a release build cannot be signed, or null when it can. */
val releaseSigning: String? = run {
    if (!keystorePropertiesFile.isFile) {
        return@run "android/key.properties is missing."
    }
    val missing = releaseSigningKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        return@run "android/key.properties has no ${missing.joinToString(", ")}."
    }
    val store = file(keystoreProperties.getProperty("storeFile"))
    if (!store.isFile) {
        return@run "the keystore that android/key.properties names (storeFile) is not at ${store.path}."
    }
    null
}

android {
    namespace = "com.rvm.rvmteam"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications 10+ needs Java 8+ API desugaring even
        // when notifications are only shown immediately (not scheduled).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.rvm.rvmteam"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigning == null) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // R8 code shrinking and resource shrinking. The Flutter Gradle plugin
            // already turns both on for release; pinned here so the release build
            // keeps them whatever the defaults become.
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

// Stops a release build early when it cannot be signed with the release key.
val checkReleaseSigning by tasks.registering {
    group = "verification"
    description = "Checks that android/key.properties can sign a release build."
    val problem = releaseSigning
    doLast {
        if (problem != null) {
            throw GradleException(
                "Release signing: $problem A release build is signed with the " +
                    "release key from android/key.properties (see \"Release " +
                    "signing\" in rvm_team_app/README.md). Debug and profile " +
                    "builds do not need it."
            )
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" || it.name == "compileFlutterBuildRelease" }
    .configureEach { dependsOn(checkReleaseSigning) }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

// Firebase Crashlytics activates only when the Firebase console config is
// present (android/app/google-services.json, Android app package
// com.rvm.rvmteam). Until KP adds that file, the app builds and runs
// normally with local-only crash logging.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
    // CI builds a release only to test it and measure its size (#50, item 11),
    // with a throwaway key: its R8 mapping files must not reach the production
    // Firebase project. GitHub Actions sets CI=true.
    if (System.getenv("CI") == "true") {
        tasks.matching { it.name.startsWith("uploadCrashlyticsMappingFile") }
            .configureEach { enabled = false }
    }
}

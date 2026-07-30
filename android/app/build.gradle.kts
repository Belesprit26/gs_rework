import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.geyserswitch.gs_orange"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.geyserswitch.gs_orange"
        minSdk = 25
        targetSdk = flutter.targetSdkVersion
        // Single source of truth: pubspec.yaml `version:` (name+code).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // key.properties is developer-local (gitignored). No silent
            // debug-signing fallback — see taskGraph check below.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Fail loudly when building a release without the signing config rather
// than producing an unsigned or debug-signed artifact.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release") } &&
        !keystorePropertiesFile.exists()
    ) {
        throw GradleException(
            "android/key.properties not found — release builds must be " +
                "signed with the upload keystore."
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

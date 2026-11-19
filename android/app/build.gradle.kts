import java.util.Properties

val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val releaseStoreFile: String? = keystoreProperties.getProperty("storeFile")

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "es.jgm1997.passport_reader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "es.jgm1997.passport_reader"
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

    buildFeatures {
        buildConfig = true
        resValues = true
    }

    flavorDimensions += "mode"
    productFlavors {
        create("real") {
            dimension = "mode"
            resValue("string", "app_name", "Passport Reader")
            buildConfigField("boolean", "ALLOW_SCREEN_CAPTURE", "false")
        }
        create("demo") {
            dimension = "mode"
            applicationIdSuffix = ".demo"
            resValue("string", "app_name", "Passport Reader DEMO")
            buildConfigField("boolean", "ALLOW_SCREEN_CAPTURE", "true")
        }
    }

    signingConfigs {
        create("release") {
            if (releaseStoreFile != null) {
                storeFile = file(releaseStoreFile)
                keyAlias = keystoreProperties.getProperty("keyAlias")
                storePassword = System.getenv("PR_STORE_PASSWORD")
                keyPassword = System.getenv("PR_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Never debug-sign a release. Without the upload key, release builds stay unsigned.
            signingConfig = if (releaseStoreFile != null) signingConfigs.getByName("release") else null
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    dependencies {
        implementation("com.google.android.play:integrity:1.5.0")
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

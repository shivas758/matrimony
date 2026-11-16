import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play Store upload key (SPEC §9.20 G). android/key.properties is NOT in git — it points at the
// keystore kept outside the project (C:/Users/<you>/wedbook-keys). Only App Bundles (`flutter
// build appbundle`, task bundleRelease) are signed with it; release APKs keep the old debug key
// so the WhatsApp installs can still update in place.
val uploadKeyProperties = Properties()
val uploadKeyFile = rootProject.file("key.properties")
if (uploadKeyFile.exists()) uploadKeyProperties.load(FileInputStream(uploadKeyFile))
val buildingBundle = gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }

android {
    namespace = "com.matrimonyagents.gandharva"
    // flutter_secure_storage (token storage) compiles against SDK 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.matrimonyagents.gandharva"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            if (uploadKeyFile.exists()) {
                keyAlias = uploadKeyProperties["keyAlias"] as String
                keyPassword = uploadKeyProperties["keyPassword"] as String
                storeFile = file(uploadKeyProperties["storeFile"] as String)
                storePassword = uploadKeyProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // App Bundle for Play → upload key; APK for WhatsApp → the old debug key.
            signingConfig =
                if (buildingBundle && uploadKeyFile.exists()) signingConfigs.getByName("upload")
                else signingConfigs.getByName("debug")
            // R8 keep rules for Razorpay Checkout (SPEC §9.19 B). Flutter
            // turns R8 on for release builds and adds its own rules.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

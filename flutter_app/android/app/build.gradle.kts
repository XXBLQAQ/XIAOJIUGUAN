import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val releaseStorePassword = providers.gradleProperty("RELEASE_STORE_PASSWORD")
    .orElse(providers.environmentVariable("RELEASE_STORE_PASSWORD"))
val releaseKeyPassword = providers.gradleProperty("RELEASE_KEY_PASSWORD")
    .orElse(providers.environmentVariable("RELEASE_KEY_PASSWORD"))
val releaseKeyAlias = providers.gradleProperty("RELEASE_KEY_ALIAS")
    .orElse(providers.environmentVariable("RELEASE_KEY_ALIAS"))
val releaseStoreFile = providers.gradleProperty("RELEASE_STORE_FILE")
    .orElse(providers.environmentVariable("RELEASE_STORE_FILE"))
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val configuredReleaseStoreFile = releaseStoreFile.orElse(
    keystoreProperties["storeFile"]?.toString() ?: ""
).get()
val configuredReleaseStorePassword = releaseStorePassword.orElse(
    keystoreProperties["storePassword"]?.toString() ?: ""
).get()
val configuredReleaseKeyAlias = releaseKeyAlias.orElse(
    keystoreProperties["keyAlias"]?.toString() ?: ""
).get()
val configuredReleaseKeyPassword = releaseKeyPassword.orElse(
    keystoreProperties["keyPassword"]?.toString() ?: ""
).get()
val hasReleaseSigning = configuredReleaseStoreFile.isNotBlank() &&
    configuredReleaseStorePassword.isNotBlank() &&
    configuredReleaseKeyAlias.isNotBlank() &&
    configuredReleaseKeyPassword.isNotBlank()

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

android {
    namespace = "cn.xxblqaq.tavern"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cn.xxblqaq.tavern"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasReleaseSigning) {
        signingConfigs {
            create("release") {
                keyAlias = configuredReleaseKeyAlias
                keyPassword = configuredReleaseKeyPassword
                storeFile = rootProject.file(configuredReleaseStoreFile)
                storePassword = configuredReleaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = hasReleaseSigning
            isShrinkResources = hasReleaseSigning
        }
    }
}

tasks.configureEach {
    if (name.contains("Release", ignoreCase = true) && !hasReleaseSigning) {
        doFirst {
            throw GradleException(
                "Release 构建需要正式签名。请在 android/key.properties 或 " +
                    "RELEASE_STORE_FILE、RELEASE_STORE_PASSWORD、" +
                    "RELEASE_KEY_ALIAS、RELEASE_KEY_PASSWORD 中完成配置。"
            )
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

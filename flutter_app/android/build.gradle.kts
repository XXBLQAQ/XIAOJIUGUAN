import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.dsl.LibraryExtension

val projectNdkVersion = "28.2.13676358"

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
    }
}

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<ApplicationExtension> {
            ndkVersion = projectNdkVersion
        }
    }
    if (name == "vibration") {
        afterEvaluate {
            extensions.configure<LibraryExtension> {
                // 兼容 vibration 插件在自身配置阶段固定 Android 33 的旧脚本。
                compileSdk = 34
                ndkVersion = projectNdkVersion
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

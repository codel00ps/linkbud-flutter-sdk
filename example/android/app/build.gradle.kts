import java.util.Base64
import java.net.URI

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val defines = (project.findProperty("dart-defines") as? String).orEmpty().split(",")
    .filter { it.isNotEmpty() }.associate {
        val pair = String(Base64.getDecoder().decode(it)).split("=", limit = 2)
        pair[0] to pair.getOrElse(1) { "" }
    }
val origin = defines["LINKBUD_ORIGIN"] ?: "https://links.example.com"
val application = defines["LINKBUD_APPLICATION"] ?: "aaaaaaaaaaaaaaaaaaaaaaaaaa"
val environment = defines["LINKBUD_ENVIRONMENT"] ?: "development"

extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "dev.linkbud.linkbud_flutter_example"
    compileSdk = 36
    ndkVersion = "29.0.14206865"
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = providers.gradleProperty("linkbudPackage").getOrElse("dev.linkbud.linkbud_flutter_example")
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["linkbudHost"] = URI(origin).host
        manifestPlaceholders["linkbudPath"] = "/l/$application/$environment/"
    }
}
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
flutter { source = "../.." }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

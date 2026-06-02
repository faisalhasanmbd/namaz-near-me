import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}

fun releaseSigningValue(projectKey: String, propertyKey: String): String? =
    (project.findProperty(projectKey) as String?) ?: keyProperties.getProperty(propertyKey)

fun releaseStoreFilePath(): File? {
    val configuredPath = releaseSigningValue("releaseStoreFile", "storeFile") ?: return null
    val configuredFile = file(configuredPath)
    if (configuredFile.exists()) return configuredFile

    val keyPropertiesRelativeFile = rootProject.file(configuredPath)
    if (keyPropertiesRelativeFile.exists()) return keyPropertiesRelativeFile

    val appRelativeFile = project.file(configuredPath.substringAfterLast('/'))
    if (appRelativeFile.exists()) return appRelativeFile

    return configuredFile
}

android {
    namespace = "com.food4u.namaznearme"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFilePath()
            storePassword = releaseSigningValue("releaseStorePassword", "storePassword") ?: ""
            keyAlias = releaseSigningValue("releaseKeyAlias", "keyAlias") ?: ""
            keyPassword = releaseSigningValue("releaseKeyPassword", "keyPassword") ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.food4u.namaznearme"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

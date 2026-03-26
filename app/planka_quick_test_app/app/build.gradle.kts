plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val baseVersionCode = 1
val baseVersionName = "0.1.0"
val envVersionCode = providers.environmentVariable("PLANKA_ANDROID_VERSION_CODE").orNull?.toIntOrNull()
val envVersionName = providers.environmentVariable("PLANKA_ANDROID_VERSION_NAME").orNull

android {
    namespace = "com.planka.quicktest"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.planka.quicktest"
        minSdk = 26
        targetSdk = 34
        versionCode = envVersionCode ?: baseVersionCode
        versionName = envVersionName ?: baseVersionName
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        viewBinding = true
        buildConfig = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.webkit:webkit:1.11.0")
    testImplementation("junit:junit:4.13.2")
}

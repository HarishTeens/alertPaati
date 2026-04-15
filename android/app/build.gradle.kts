plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.alertpaati"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.alertpaati"
        // LiteRT LLM Inference requires API 26+; ConnectionService requires API 23+
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // Required for LiteRT native libs
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Disable both together — shrinkResources requires minify to be on.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/DEPENDENCIES"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // MediaPipe LLM Inference API — the production-ready path for Gemma on Android.
    // LlmInference.Options.setModelPath() accepts raw .bin model files directly;
    // a .task bundle is NOT required.
    implementation("com.google.mediapipe:tasks-genai:0.10.22")

    // Coroutines for async inference
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // JSON for MethodChannel result maps
    implementation("org.json:json:20240303")
}

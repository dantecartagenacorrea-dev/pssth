import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Llave de subida a Google Play: android/key.properties (fuera de git).
// Sin ese archivo, la versión de prueba se firma con la llave de depuración.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.lectorpdf.lector_pdf"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lectorpdf.lectorPdf"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyProperties.isNotEmpty()) {
            create("upload") {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    // Bibliotecas nativas comprimidas dentro del APK: la descarga baja a la
    // mitad (101 -> ~48 MB). Al instalar se descomprimen.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyProperties.isNotEmpty()) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
            // Sin recorte de código ni recursos: R8 rompía librerías nativas
            // (sherpa-onnx/JNI, ML Kit) y la app se cerraba al abrir en dispositivos reales.
            isMinifyEnabled = false
            isShrinkResources = false
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

dependencies {
    // OCR y detección de idioma en el dispositivo (Google ML Kit, gratuito, sin red).
    // El lector de texto lo trae Google Play Services (11 MB menos en la app); se
    // pide al instalar y al abrir la app, así funciona sin red desde el inicio.
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
    // Códigos QR de las fotos, también desde Play Services (casi no suma peso).
    implementation("com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1")
    implementation("com.google.mlkit:language-id:17.0.6")
    // Escáner de documentos (recorta, endereza, varias páginas) vía Google Play Services.
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    // FileProvider para compartir el audio generado (AndroidX, gratuito).
    implementation("androidx.core:core-ktx:1.13.1")
}

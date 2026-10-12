plugins {
    id("com.android.application")
}

dependencies {
    implementation("androidx.core:core:1.17.0")
}

android {
    namespace = "com.stillopen.fixture"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.stillopen.fixture"
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }
}

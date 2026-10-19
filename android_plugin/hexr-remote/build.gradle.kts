plugins {
    id("com.android.library")
}

android {
    namespace = "com.microtube.hexr.godot.remote"
    compileSdk = 35

    defaultConfig {
        // Godot 4.6's own minimum.
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    // Supplied by the game's Godot build at runtime. Compiled against the oldest supported
    // version so the plugin loads on every newer one.
    compileOnly("org.godotengine:godot:4.6.0.stable")
    testImplementation("junit:junit:4.13.2")
}

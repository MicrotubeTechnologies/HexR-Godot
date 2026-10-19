// The HexR Godot addon's Android plugins (Godot Android plugin v2). Each module builds an AAR
// that `copyAarsToAddon` places in addons/hexr/android/bin, where the addon's export plugin
// hands it to Godot's Gradle build.
//
// Java only, no AndroidX and no Kotlin: the AARs are merged into whatever Gradle build template
// the game uses, alongside the OpenXR vendors plugin, and every dependency here is one more
// thing that can clash with theirs.
plugins {
    id("com.android.library") version "8.13.0" apply false
}

tasks.register<Copy>("copyAarsToAddon") {
    dependsOn(":hexr-ble:assembleDebug", ":hexr-ble:assembleRelease",
        ":hexr-remote:assembleDebug", ":hexr-remote:assembleRelease")
    from("hexr-ble/build/outputs/aar", "hexr-remote/build/outputs/aar")
    include("*.aar")
    into("../addons/hexr/android/bin")
}

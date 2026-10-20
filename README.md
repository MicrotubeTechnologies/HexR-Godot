# HexR for Godot ℹ️

The **HexR** haptic glove SDK for **Godot 4**: Bluetooth connection to the glove, the haptics API,
touch points on tracked hands, ready-made scene nodes, a floating menu, an editor dock and
HexR Remote. It sends the same bytes as the HexR Unity package (`com.microtube.hexr` 0.10.5), so
the glove, the HexR Tester and the HexR Companion behave the same with Godot apps.

> [!NOTE]
> API reference: [docs/API.md](docs/API.md), also in Godot's built-in help (**F1**, search `HexR`).
> Guides: the Godot section of the [HEXR documentation](https://microtube.tech/hexr-docs).
> A ready-to-run project: [HexR-Developer-Tutorial-Godot](https://github.com/MicrotubeTechnologies/HexR-Developer-Tutorial-Godot).

---

## 📑 Contents

| Section | What's inside |
|---|---|
| [🚀 Install](#-install) | Requirements, installing the addon, headset setup |
| [🧤 Using it](#-using-it) | The `HexR` autoload, the haptics calls, the scene nodes |
| [🧩 What runs where](#-what-runs-where) | Bluetooth on each platform, and what is validated |
| [🛠️ Developing the addon](#️-developing-the-addon) | Repository layout, tests, native builds, releases |
| [📄 License](#-license) | MIT, plus third-party notices |

---

## 🚀 Install

| Requirement | Details |
|---|---|
| **Godot 4.6 or newer** | Tested on 4.7.2. The standard build; .NET is not needed |
| **Android export** | Android SDK, JDK 17, export templates, **Use Gradle Build** in the preset |
| **OpenXR Vendors plugin** | 5.1.0 or newer, for Meta Quest and PICO |

1. Download `HexR-Godot-<version>.zip` from this repository's **Releases** (or the **Addon zip**
   artifact of a CI run) and unzip it into your project, so you have `res://addons/hexr/`.
2. **Project → Project Settings → Plugins** → enable **HexR**. It adds the `HexR` autoload, names
   physics layers 20 (`hexr_touch`) and 21 (`hexr_interactable`), and adds the **HexR** dock.
3. **Project → Tools → HexR → Create HexR Rig** in your XR scene, then **Add HexR Menu**.
4. HexR dock → **Setup** → *Check project and open scene*, and **Fix** anything red.

> [!IMPORTANT]
> The release zip carries the native libraries (`android/bin/*.aar`, `bin/windows/*.dll` and the
> stubs). A plain clone of this repository does not: they are built by CI.

---

## 🧤 Using it

```gdscript
HexR.connect_hand(HaptGloveHandler.HandType.LEFT)            # asks for Bluetooth permission where needed

var hand := HexR.controller(HaptGloveHandler.HandType.LEFT)  # the scene's Pressure Controller
hand.custom_single_haptics(Haptics.Finger.INDEX, true, 0.8, 1.0, true)
hand.custom_single_vibrations(Haptics.Finger.PALM, true, 0.7, 18.0, true)
HexR.left.release_all_channels()
```

| Node | What it does |
|---|---|
| `HexRRig` | Under your `XROrigin3D`: tracked hands with touch points, and both Pressure Controllers |
| `HexRGrabbable` | Pinch or palm grab of a `RigidBody3D`, each touching finger pressed |
| `HexRPhysicalButton` | A button pressed by a fingertip |
| `SpecialHaptics` | Zones: custom vibration or pressure, fountain, rain drop, heart beat, hand squeeze |
| `ProximityCheck`, `HexRUsable` | Hand-near check for code-driven haptics; curl-to-use |
| `HexRInteractableHaptics` | Pressure while a Godot XR Tools pickable is held |
| `HexRFloatingMenu` | Connect, battery and a live haptics readout, pressed with a fingertip |
| `HexRRemote` | The HexR Companion's link: status, gloves, scenes, commands, view and sound |

Every class, signal, property and method is in [docs/API.md](docs/API.md), generated from the
addon's doc comments, and in Godot's built-in help (**F1**, search `HexR`).

---

## 🧩 What runs where

| Platform | Bluetooth | Status |
|---|---|---|
| Meta Quest, PICO (Android) | `HexRBle` Java plugin (`android_plugin/hexr-ble`) | Quest 3: connect and haptics run with a glove. PICO: not yet run on hardware |
| Windows 10/11 x64, editor and builds | `HexRBleWinRT` C++/WinRT extension (`gdextension/`) | Builds in CI; scanning checked on hardware; glove session pending |
| macOS, Linux | Stub extension | Loads cleanly; simulated gloves |
| HexR Remote | GDScript (`addons/hexr/remote/`) + `hexr-remote` capture plugin | Discovery and status checked on a Quest 3 with the Unity probe; view and sound pending on hardware |

---

## 🛠️ Developing the addon

```
addons/hexr/        the addon (what ships)
android_plugin/     Gradle project: hexr-ble and hexr-remote AARs (Java, no AndroidX)
gdextension/        C++/WinRT Bluetooth extension, godot-cpp submodule (godot-4.5-stable)
tests/              headless GDScript tests, fixtures, the Remote harness, smoke scenes
tools/              golden-frame generator, Remote conformance check, version and library checks
docs/               API.md (generated), RemoteProtocol.md (shared with the Unity package)
```

```bash
# GDScript tests (Godot 4.6+), headless; exits with the number of failures
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd

# Wire-format fixtures: regenerate, or check they are current
python tools/gen_golden_frames.py [--check]

# The API reference, from the ## doc comments: regenerate after changing them
python tools/gen_api_docs.py [--check]

# HexR Remote against the Unity package's own probe
python tools/remote_conformance.py --godot path/to/godot

# Android plugins and their JVM tests; copies the AARs into addons/hexr/android/bin
cd android_plugin && ./gradlew :hexr-ble:testDebugUnitTest copyAarsToAddon
```

The Windows extension needs MSVC with the Windows SDK (`scons platform=windows target=template_debug`).
CI runs the GDScript tests on every push. The native code (the Android plugins, the Windows extension
on `windows-2022`, the Linux, macOS and Android stubs) and the addon zip build only on a `v*` tag or
a manual run (**Actions → CI → Run workflow**), because they take most of the CI minutes. A `v*` tag
publishes the zip as a release; `tools/check_version.py` makes sure `plugin.cfg`,
`HexRManager.VERSION` and `CHANGELOG.md` agree first, and `tools/check_gdextension.py` that every
library the extension lists is in the zip.

The protocol must stay byte-identical to the Unity package: change `tests/fixtures/golden_frames.json`
or `docs/RemoteProtocol.md` only together with the Unity package and the HexR Companion.

---

## 📄 License

MIT, see [LICENSE](LICENSE) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

# HexR for Godot ℹ️

The **HexR** haptic glove SDK for **Godot 4**, shaped like the HexR Unity package: the same class
and method names, the same floating menu, the same HexR menu and HexR Tools. Bluetooth connection
to the glove, the haptics API, touch points on tracked hands, ready-made scene nodes and HexR Remote. It sends the same bytes as the HexR Unity package (`com.microtube.hexr` 0.10.5), so
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
| **OpenXR Vendors plugin** | 5.1.0 or newer, for Meta Quest and PICO (HexR Tools installs it for you) |

Where Unity developers paste the package's git URL into Package Manager, Godot developers install
an addon folder:

1. **Get the addon.** Download `HexR-Godot.zip` from this repository's
   [latest release](https://github.com/MicrotubeTechnologies/HexR-Godot/releases/latest) and
   unzip it into your project, so you have `res://addons/hexr/`. (A Godot Asset Library listing,
   for installing from the editor's AssetLib tab, is on its way.)
2. **Enable it:** **Project → Project Settings → Plugins → HexR**. A **HexR** menu appears in the
   editor's menu bar, and the **HexR Tools** dock under the Inspector, as in Unity.
3. **HexR Tools → Project Setup:** install the OpenXR Vendors plugin, apply the XR settings and add
   the Meta Quest and PICO export presets. Install the Android build template from the Project menu.
4. **HexR → Create HexR Rig** in your 3D scene, then **HexR → Add HexR Menu** (or **HexR → Create
   Demo Scene** for all of it at once).
5. **HexR → Troubleshoot → Validate Scene Setup**, and **Fix all**.

To update, use **HexR Tools → Project Setup → Check for updates** (Unity: Package Manager →
Update). Coming from 0.1? Delete `addons/hexr` first, then run **HexR → Migration → Upgrade 0.1
Scenes**: see [CHANGELOG.md](CHANGELOG.md).

> [!IMPORTANT]
> The release zip carries the native libraries (`android/bin/*.aar`, `bin/windows/*.dll` and the
> stubs). A plain clone of this repository does not: they are built by CI.

---

## 🧤 Using it

The classes and calls are the Unity package's, in Godot's snake_case:

```gdscript
HexR.connect_hand(HaptGloveHandler.HandType.LEFT)          # Unity: HexRManager.Instance.Connect(...)

var tracker := HexR.controller(HaptGloveHandler.HandType.LEFT)   # the hand's PressureTrackerMain
tracker.trigger_all_haptics_increase(0.5)                  # Unity: TriggerAllHapticsIncrease(0.5f)
tracker.custom_single_vibrations(Haptics.Finger.PALM, true, 0.7, 18.0, true)

var glove := HexR.left_hand                                # Unity: HexRManager.Instance.leftHand
glove.bt_send(glove.haptics.hexr_pressure(Haptics.Finger.INDEX, true, 0.8, 1.0))
glove.release_all_channels()
```

| Node | What it does |
|---|---|
| `HexRRig` | Unity's "HexR Main": under your `XROrigin3D`, both tracked hands with their `HapticFingerTrigger`s and both `PressureTrackerMain`s; starts XR |
| `HexRGrabbable` | Pinch or palm grab of a `RigidBody3D`, each touching finger pressed |
| `HexRPhysicalButton` | A button pressed by a fingertip |
| `SpecialHaptics` | Zones: custom vibration or pressure, fountain, rain drop, heart beat, hand squeeze |
| `ProximityCheck`, `HexRUsable` | Hand-near check for code-driven haptics; curl-to-use |
| `HexRInteractableHaptics` | Pressure while a Godot XR Tools pickable is held |
| `HexRFloatingMenu` | The HexR menu in Unity's look: connect, colliders, haptics readout, scenes, demos |
| `HexRRemote` | The HexR Companion's link: status, gloves, scenes, commands, view and sound |

Every class, signal, property and method is in [docs/API.md](docs/API.md), generated from the
addon's doc comments, and in Godot's built-in help (**F1**, search `HexR`).

<details>
  <summary>Coming from Unity: where Godot differs, and why</summary>

<br>

| Unity | Godot | Why |
|---|---|---|
| `HexRManager.Instance` | the `HexR` autoload (or `HexRManager.instance`) | Godot's singletons are autoloads |
| `Connect` / `Disconnect` / `IsConnected(hand)` | `connect_hand` / `disconnect_hand` / `is_hand_connected(hand)` | every Godot object already has `connect`, `disconnect` and `is_connected` |
| `TriggerAllHapticsIncrease(…)` | `trigger_all_haptics_increase(…)` | Godot's snake_case; enum values are UPPER_CASE |
| `HEXRPressure` overloads | `hexr_pressure`, `hexr_pressure_multi`, `hexr_vibration_ramped`, … | GDScript has no overloads |
| UnityEvents `OnGrab`, `onPressed` | signals `grabbed`, `pressed` | Godot's signals |
| `Gravity` on HexRGrabbable | `gravity_on_release` | `Area3D` already has `gravity` |
| `HapticFingerTrigger.FingerType` | `Haptics.Finger` everywhere | one channel order, the glove's |
| Build Settings scene list | Project Settings → HexR → Scenes (`hexr/scenes`) | Godot has no Build Settings list |
| Auto Setup, hand roots | none needed | the touch points follow the OpenXR hand tracker directly |
| XRI / Meta Interaction SDK backends | Godot XR Tools | Godot's XR toolkit |

</details>

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

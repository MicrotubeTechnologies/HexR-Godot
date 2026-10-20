# Changelog

The HexR Godot addon. Versions follow semver; the HexR Remote protocol level it speaks is
`HexRManager.PROTOCOL_VERSION` (the Unity package version it matches).

## 0.2.0 (2026-10-20)

HexR for Godot now reads like the HexR Unity package: Unity's class names, Unity's member names
in Godot's snake_case, Unity's floating menu, and Unity's editor menu and tools. Still a preview:
the API may change before 1.0.

**Upgrading from 0.1:** delete `addons/hexr` before unzipping 0.2 (or let the plugin offer to
remove the 0.1 scripts it finds), then run **HexR > Migration > Upgrade 0.1 Scenes** *before*
opening your scenes. Until then the components still read their 0.1 property names and warn once.

| 0.1 | 0.2 (Unity's name) |
|---|---|
| `HexRGlove` | `HaptGloveHandler` |
| `HexRHaptics` | `Haptics` |
| `HexRTouchPoint` | `HapticFingerTrigger` |
| `HexRPressureController` | `PressureTrackerMain` |
| `HexRFingerUseTracking` | `FingerUseTracking` |
| `HexRProximityCheck` | `ProximityCheck` |
| `HexRSpecialHaptics` | `SpecialHaptics` |
| `HexRTypes.Hand` / `BatteryState` | `HaptGloveHandler.HandType` / `BatteryState` |
| `HexRTypes.Finger` / `HapticMode` / `Op` | `Haptics.Finger` / `HapticMode` / `FunIndex` (`FI_SET_PRESSURE`, …) |
| `HexR.left` / `HexR.right` (gloves) | `HexR.left_hand` / `HexR.right_hand` |
| `HexR.left_hand` / `right_hand` (tracked hands) | `HexR.left_tracked_hand` / `right_tracked_hand` |
| glove `hand`, `connect_toggle()`, `get_finger_positions()`, `custom_device_name` | `which_hand`, `bt_connection()`, `get_finger_position()`, `optional_custom_device_name` |
| glove signals without a hand | every glove signal carries the hand |
| `hand` / `finger` on touch points, controllers, tracked hands | `hand_type` / `finger_type` |
| `trigger_pulse_all()` | `trigger_pulse_it()` |
| HexRGrabbable `grab_type` (`GrabType.PINCH`), `target` | `type_of_grab` (`Options.PINCH_GRAB`), `the_object` |
| HexRPhysicalButton / HexRUsable `fingers` bitmask | per-finger tick boxes, as in Unity |
| SpecialHaptics `effect` (`Effect.FOUNTAIN`…), `haptic_strength`, `vibration_frequency`, `heart_beat` | `type_of_haptics` (`Options.FOUNTAIN_EFFECT`…), `haptic_strength_value`, `vibrations_frequency_value`, `heartbeat` |
| menu and HexR Remote `scenes` lists | the project setting `hexr/scenes`, Godot's stand-in for Build Settings |

Defaults now follow Unity: a new SpecialHaptics zone is custom vibrations, a new HexRUsable needs
all five fingers. The migration writes your 0.1 scenes' old defaults out explicitly.

- **API:** `HexRManager.instance`, `begin_connect`, `connect_left_bt` / `connect_right_bt`;
  `HaptGloveHandler.bt_disconnection`, `set_battery_level_update_interval`; PressureTrackerMain's
  `thumb_pressure` … `tank_pressure`, `glove_handler`, `collision_near_hand`; new
  `HaptGloveCollidersVisualizer` and `SceneLoader`; `HexRRemote.phones_watching()`.
- **Floating menu:** rebuilt in the Unity panel's look and layout (HEXR MENU header, GLOVES,
  VIEW, HAPTICS, SCENES, DEMOS) and behaviour: a press volume per button that fires on entry
  and holds the press, spawning to the left, one panel for the session, an editor preview.
- **Editor:** a top-level HexR menu with Unity's items (Create Demo Scene, Import Tutorial
  Content, Troubleshoot, Migration); the HexR Tools dock with Unity's three tabs (Haptics Tester
  with a call preview, HexR Setup with Fix all, Project Setup that installs the OpenXR Vendors
  plugin and XR Tools, adds Quest and PICO presets and updates HexR); inspector helpers.
- **Starting XR:** `HexRRig.start_xr` switches the viewport to the headset, as Unity's XR
  Plug-in Management does.
- **Install:** each release is also published for the Godot Asset Library, and
  `releases/latest/download/HexR-Godot.zip` always gives the newest.
- **Docs:** `docs/API.md`, generated from the doc comments and checked by CI.

## 0.1.0 (2026-10-19)

First Godot release.

- Glove protocol identical to the Unity package 0.10.5, byte for byte (float32 encoder,
  555 golden frames), with the HexR Companion's resynchronising telemetry decoder.
- Bluetooth on Android headsets (HexRBle plugin) and on Windows (HexRBleWinRT extension),
  simulated gloves everywhere else.
- Connect campaign as in the Unity package: scan or direct reconnect, 1/2/4/8 s backoff,
  60 s give-up, 20 s watchdog, release before disconnect, on pause and on quit.
- Fixes carried over from the Unity package's known issues: the pump command no longer
  sends "stop" on the second connection of a session.

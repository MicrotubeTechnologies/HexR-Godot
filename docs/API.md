# HexR Godot addon: API reference

Addon 0.1.0. Generated from the addon's doc comments by `tools/gen_api_docs.py`;
edit those, not this file. The same text is in Godot's built-in help: press **F1** in the
editor and search for `HexR`.

Hands and fingers are the `HaptGloveHandler.HandType` and `Haptics.Finger` enums (`int` in
signatures). Intensities are 0.1–1 (about 15–50 kPa); frequencies are in Hz.

## Contents

- **Gloves and connection**: [`HexRManager`](#hexrmanager), [`HaptGloveHandler`](#haptglovehandler), [`Haptics`](#haptics), [`HexRTypes`](#hexrtypes), [`HexRFrameDecoder`](#hexrframedecoder)
- **Hands**: [`HexRRig`](#hexrrig), [`HexRTrackedHand`](#hexrtrackedhand), [`HapticFingerTrigger`](#hapticfingertrigger), [`FingerUseTracking`](#fingerusetracking)
- **Haptics**: [`PressureTrackerMain`](#pressuretrackermain)
- **Scene nodes**: [`HexRGrabbable`](#hexrgrabbable), [`HexRPhysicalButton`](#hexrphysicalbutton), [`SpecialHaptics`](#specialhaptics), [`HexRUsable`](#hexrusable), [`ProximityCheck`](#proximitycheck), [`HexRInteractableHaptics`](#hexrinteractablehaptics), [`HexRXRToolsBinding`](#hexrxrtoolsbinding)
- **Menu and HexR Remote**: [`HexRFloatingMenu`](#hexrfloatingmenu), [`HexRRemote`](#hexrremote)
- [Internals](#internals)

---

# Gloves and connection

## HexRManager

*extends `Node` · `addons/hexr/core/hexr_manager.gd` · autoload `HexR`*

The HexR autoload, `HexR`: both gloves, their Bluetooth link and the scene's Pressure Controllers. Port of the Unity package's HexRManager.

```gdscript
HexR.connect_hand(HaptGloveHandler.HandType.LEFT)
HexR.glove_connected.connect(func(hand): print(HexRTypes.hand_name(hand), " connected"))
HexR.controller(HaptGloveHandler.HandType.LEFT).single_index_haptic(0.8)
```

It survives scene changes, as autoloads do. Scenes bring their own rig (tracked hands and Pressure Controllers), which registers itself here.

### Signals

- **`glove_connected(hand: int)`**
- **`glove_disconnected(hand: int)`** — A glove's link went down. `is_hand_connecting()` is true if it is reconnecting by itself.
- **`glove_connect_failed(hand: int)`** — One connect attempt failed; the campaign may still retry.
- **`connect_attempt_ended(hand: int)`** — A connect campaign ended without a connection: it gave up, was cancelled or was not permitted.
- **`battery_state_changed(hand: int, state: int)`**
- **`pump_changed(hand: int, on: bool)`**
- **`status_changed(hand: int, text: String)`** — A glove's status text changed (what the floating menu shows).
- **`device_found(id: String, device_name: String, rssi: int)`** — A device was seen during a scan. For building a device picker.
- **`controllers_changed`** — A Pressure Controller registered or unregistered.

### Properties

- **`transport: HexRBleTransport`**
- **`device_store: HexRDeviceStore`**
- **`left: HaptGloveHandler`**
- **`right: HaptGloveHandler`**
- **`left_controller: PressureTrackerMain`** — The scene's Pressure Controllers, set when they enter the tree.
- **`right_controller: PressureTrackerMain`**
- **`left_hand: HexRTrackedHand`** — The scene's tracked hands, set when they enter the tree.
- **`right_hand: HexRTrackedHand`**
- **`drive_from_process := true`** — When false, nothing advances until `tick()` is called (tests drive time themselves).

### Methods

- **`static get_instance() -> HexRManager`** — The running HexR manager: the HexR autoload, or one made current with `make_current()`. Addon scripts use this rather than the autoload's name.
- **`make_current() -> void`** — Makes this manager the one components talk to (tests, editor tools).
- **`setup(p_transport: HexRBleTransport, store: HexRDeviceStore) -> void`** — Uses `p_transport` for both gloves. Called automatically with the platform's transport; call it first to supply another (tests, simulated gloves).
- **`tick(now_ms: int) -> void`** — Advances the transport and both gloves to `now_ms`.
- **`glove(hand: int) -> HaptGloveHandler`**
- **`connect_hand(hand: int) -> void`** — Connects that hand's glove, asking for Bluetooth permission first where the platform needs it. Does nothing if it is connected or already connecting, so it is safe to call at any time.
- **`disconnect_hand(hand: int) -> void`** — Releases every channel on that hand's glove and disconnects it, or cancels a connect in progress.
- **`toggle_hand(hand: int) -> void`** — What a menu's Connect button does: connect, cancel a connect in progress, or disconnect.
- **`is_hand_connected(hand: int) -> bool`**
- **`is_hand_connecting(hand: int) -> bool`** — True while waiting for permission, scanning, connecting or waiting to retry.
- **`controller(hand: int) -> PressureTrackerMain`** — The Pressure Controller for `hand`, or null if the scene has none.
- **`tracked_hand(hand: int) -> HexRTrackedHand`** — The tracked hand for `hand`, or null if the scene has none.
- **`finger_use(hand: int) -> FingerUseTracking`** — How curled each finger of `hand` is, or null without a tracked hand.
- **`shutdown() -> void`** — Releases and disconnects both gloves.

### Constants

- **`VERSION := "0.1.0"`** — The addon's version.
- **`PROTOCOL_VERSION := "0.10.5"`** — The HexR Remote protocol level this addon implements (the Unity package version it matches).

## HaptGloveHandler

*extends `Node` · `addons/hexr/core/hapt_glove_handler.gd`*

One glove: its Bluetooth connection, the commands sent to it and the readings it sends back. Port of the Unity package's HaptGloveHandler. Reach them as `HexR.left` and `HexR.right`.

Connecting runs a campaign: it scans (or connects straight to the remembered glove), and when an attempt fails it retries after 1, 2, 4, 8, 8... seconds, giving up after 60 s. A glove that drops reopens a campaign by itself. Calling `connect_toggle()` while a campaign runs cancels it; on a connected glove it disconnects.

Before the link closes, on pause and on quit, every channel is released: once disconnected the glove keeps whatever it was last told.

### Signals

- **`bluetooth_connected`** — The link is up.
- **`bluetooth_disconnected`** — The link went down, whether asked for or lost. `is_connecting()` tells them apart: it is true after a drop, because a reconnect campaign has started.
- **`bluetooth_connection_failed`** — One connect attempt failed. More may follow; see `connect_campaign_ended`.
- **`connect_campaign_ended`** — The connect campaign ended without a connection (gave up, cancelled or not permitted).
- **`pump_changed(on: bool)`**
- **`battery_state_changed(state: int)`**
- **`device_found(id: String, device_name: String)`**
- **`status_changed(text: String)`**

### Properties

- **`hand: int = HaptGloveHandler.HandType.LEFT`** — Which hand this glove is.
- **`haptics := Haptics.new()`** — Builds the commands and records the last one per channel.
- **`decoder := HexRFrameDecoder.new()`** — The glove's latest readings.
- **`coalescer := HexRWriteCoalescer.new()`** — Batches commands into at most one write per interval.
- **`release_when_paused := true`** — Release every channel when the app is paused (on a headset, when it is taken off). A paused app cannot release anything itself, so without this the glove keeps pressing until it resumes.
- **`use_custom_device_name := false`** — Match this advertised name instead of "HaptGloveAR Left/Right".
- **`custom_device_name := ""`**
- **`source_pressure := 80`** — Air source pressure sent with the pump command.
- **`auto_start_pump := true`** — Send the pump command 2 s after connecting, as the Unity package does.
- **`verbose := false`** — Log connection steps.
- **`ble_connected := false`** — True while the link is up.
- **`device_id := ""`** — The connected glove's id.
- **`mtu := 0`** — The negotiated MTU while connected.
- **`status_text := ""`** — Human-readable connection status, for menus.
- **`battery_state: int = HaptGloveHandler.BatteryState.FULL`**

### Methods

- **`setup(p_hand: int, hub: Object, transport: HexRBleTransport, store: HexRDeviceStore) -> void`**
- **`target_device_name() -> String`** — The advertised name this glove matches.
- **`side() -> String`**
- **`connect_toggle() -> void`** — Connects, cancels a campaign in progress, or disconnects, depending on the state. Prefer `HexRManager.connect_hand()`, which also asks for Bluetooth permission.
- **`cancel_connect() -> void`** — Stops a connect campaign. Does nothing when connected or idle.
- **`is_connecting() -> bool`** — True while a connect campaign is under way: scanning, connecting or waiting to retry.
- **`get_remembered_device_id() -> String`**
- **`remember_device(id: String) -> void`** — Targets this physical glove from now on (for example one picked from `device_found`).
- **`forget_device() -> void`**
- **`connect_to_device(id: String) -> void`** — Remembers `id` and connects to it.
- **`tick(now_ms: int) -> void`** — Advances timers and flushes queued commands. HexR calls this every frame.
- **`bt_send(data: PackedByteArray) -> bool`** — Sends frames built by `haptics` (or [`Haptics`](#haptics) directly). Queued and batched where the platform needs it. Dropped while disconnected: a command for a grab that is over is better lost than delivered late.
- **`release_all_channels() -> void`** — Releases every channel.
- **`release_channels(fingers: Array) -> void`** — Releases `fingers` on both the pressure and the vibration path.
- **`air_pressure_source_control() -> void`** — Starts the air pump, or stops it if started (as the Unity package's AirPressureSourceControl).
- **`shutdown(why: String = "shutdown") -> void`** — Releases the glove and closes the link. HexR calls this on quit.
- **`get_battery_level() -> float`** — Battery as a 0..1 fraction; 0 until the glove reports it.
- **`get_air_pressure() -> PackedInt32Array`** — Raw pressure readings as whole numbers (Thumb..Palm, then the air source), as the Unity package returns them.
- **`get_air_pressure_kpa() -> PackedFloat32Array`** — Pressure readings in gauge kPa (Thumb..Palm, then the air source).
- **`get_finger_positions() -> PackedInt32Array`** — Finger position sensor readings, Thumb..Pinky.

### Enums

- **`HandType { LEFT, RIGHT }`** — Which hand a glove, controller or touch point belongs to.
- **`BatteryState { FULL, MEDIUM, LOW }`** — The glove's battery, from its battery level.

### Constants

- **`TELEMETRY_MIN_MTU := 77`** — Notifications need MTU 77 to carry the glove's 74-byte bundle.

## Haptics

*extends `RefCounted` · `addons/hexr/core/haptics.gd`*

Builds the glove's haptic command frames (port of the Unity package's HaptGlove.Haptics).

Each glove owns one of these. The builders return bytes to send with `HaptGloveHandler.bt_send()`; they also record the last command per channel, which the floating menu's readout and HexR Remote's haptics feed read back. That record is commanded intent: the glove does not acknowledge commands.

Intensity is 0.1..1 and maps linearly to 15..50 kPa. Speed is 0.1..1, the ramp rate. Out-of-range values are clamped, not rejected.

### Methods

- **`get_channel_state(finger: int) -> ChannelState`** — The last command sent to `finger`.
- **`get_last_active_state(finger: int) -> ChannelState`** — The last command that turned `finger` on, kept after it goes off again. A tap can be switched on and off within one frame, and polling `get_channel_state()` would miss it.
- **`get_activation_count(finger: int) -> int`** — How many commands have turned `finger` on. Changes on every trigger, including a repeat of the same value.
- **`static vibration_pressure_and_peak(frequency: float, intensity: float) -> Array`** — Unity GetVibIntensity: the pressure and peak ratio a vibration of `frequency` uses for a 0.1..1 intensity. At 5 Hz and above the pump runs flat out and intensity sets the peak ratio; below that intensity sets the pressure.
- **`hexr_pressure(finger: int, on: bool, intensity: float, speed: float = 1.0) -> PackedByteArray`** — Steady pressure on one channel (function 0x04). `on`: true to press, false to release. `intensity`: 0.1..1. `speed`: 0.1..1.
- **`hexr_pressure_multi(fingers: Array, states: Array, intensities: Array, speeds: Array) -> PackedByteArray`** — `hexr_pressure()` for several channels, concatenated into one write.
- **`hexr_vibration(finger: int, on: bool, frequency: float, intensity: float) -> PackedByteArray`** — Vibration on one channel (function 0x07). `frequency`: 0.1..40 Hz. `intensity`: 0.1..1; at 5 Hz and above it sets the peak ratio, below that the pressure.
- **`hexr_vibration_multi(fingers: Array, states: Array, frequencies: Array, intensities: Array) -> PackedByteArray`** — `hexr_vibration()` for several channels, concatenated into one write.
- **`hexr_vibration_ramped(finger: int, on: bool, frequency: float, intensity: float, peak_ratio: float, speed: float, end_intensity: float) -> PackedByteArray`** — Low-frequency vibration with a shaped pulse (function 0x09). `frequency`: 0.1..2 Hz. `peak_ratio`: 0.2..0.8, the share of each cycle spent at peak. `end_intensity`: the pressure to hold after the vibration; below 0.1 holds none.
- **`hexr_pulse(finger: int, on: bool, frequency: float, intensity: float, pulse_count: int) -> PackedByteArray`** — A counted burst of pulses (function 0x08). `frequency`: 0.1..40 Hz. `pulse_count`: 1..1000.
- **`hexr_pulse_ramped(finger: int, on: bool, frequency: float, intensity: float, peak_ratio: float, speed: float, pulse_count: int, end_intensity: float) -> PackedByteArray`** — A counted burst of shaped low-frequency pulses (function 0x0A). `frequency`: 0.1..2 Hz.
- **`build_release(fingers: Array = HexRTypes.ALL_FINGERS) -> PackedByteArray`** — Releases `fingers` on both paths: a vibration exit, then a pressure exit, per channel. A pressure exit alone does not stop a vibration of 5 Hz or more. Byte-identical to the Unity package's release (216 bytes for all six channels).
- **`static pump_control(start: bool, source_kpa: int = 80) -> PackedByteArray`** — Air-source pump control (function 0x02). Current firmware ignores it; it is sent for parity with the Unity package.
- **`static set_pid(kp: float, ki: float, kd: float) -> PackedByteArray`** — PID gains for every channel's pressure loop (function 0x05). Changing them changes how every haptic feels; leave them alone unless Microtube asks.

### Enums

- **`Finger { THUMB, INDEX, MIDDLE, RING, PINKY, PALM }`** — Haptic channels in wire order (the channel byte, 0..5).
- **`HapticMode { OFF, PRESSURE, VIBRATION, PULSE }`** — What a channel was last told to do.
- **`FunIndex { FI_AIR_PRESSURE, FI_STABLE_PRESSURE_CTRL, FI_SET_PRESSURE_DEPRECATED, FI_SET_PRESSURE, FI_SET_PID, FI_SET_BATTERY_LED, FI_SET_VIBRATION, FI_SET_PULSE, FI_SET_VIB_SPEED, FI_SET_PULSE_SPEED }`** — Outbound function indices (app to glove), as the Unity package names them.

## HexRTypes

*extends `RefCounted` · `addons/hexr/core/hexr_types.gd`*

Wire-protocol constants and small helpers shared by the addon. The enums a game uses live where the Unity package has them: `HaptGloveHandler.HandType`, `HaptGloveHandler.BatteryState`, `Haptics.Finger`, `Haptics.HapticMode` and `Haptics.FunIndex`.

### Methods

- **`static hand_name(hand: int) -> String`**
- **`static finger_name(finger: int) -> String`**
- **`static default_device_name(hand: int) -> String`**
- **`static hand_from_device_name(device_name: String) -> int`** — Which hand an advertised name belongs to, or -1. The hand is carried only by the name; the command bytes are identical for both gloves.

### Enums

- **`InOp { PRESSURE, MICROTUBE, CLUTCH_ACTIVATED, BATTERY }`** — Inbound function indices (glove to app, notifications).

### Constants

- **`STATE_ENTER := 0`** — Channel state byte: 0 applies, 2 releases. 1 ("stay") does nothing on the glove.

## HexRFrameDecoder

*extends `RefCounted` · `addons/hexr/core/hexr_frame_decoder.gd`*

Resynchronising parser for the glove's notifications (port of the HexR Companion's FrameDecoder).

Inbound frames are `[len][func][field...][xor]`, where xor is the XOR of every byte before it. Notifications need not line up with frames, so this buffers, checks the length and checksum, and only then consumes. A frame that fails costs one byte, not the buffer.

The glove sends three frames 50 times a second once notifications are on: finger positions (0x04), pressures (0x01) and battery (0x06).

### Properties

- **`pressure_raw: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])`** — Raw pressure readings: Thumb, Index, Middle, Ring, Pinky, Palm, then the air source. Firmware reports gauge kPa; some gloves report absolute pascals. See `raw_to_kpa()`.
- **`finger_position: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])`** — Finger position sensor readings, Thumb..Pinky.
- **`battery: float = -1.0`** — Battery as a 0..1 fraction, or -1 until the glove reports it.
- **`seen: bool = false`** — True once any valid frame has arrived.
- **`bad_frames: int = 0`** — Frames that failed their checksum or were shorter than their function implies.
- **`pressure_frames: int = 0`** — How many valid frames of each kind have arrived.
- **`position_frames: int = 0`**
- **`battery_frames: int = 0`**

### Methods

- **`reset() -> void`**
- **`feed(data: PackedByteArray) -> int`** — Feeds one notification. Returns how many frames it completed.
- **`static raw_to_kpa(raw: float) -> float`** — Gauge kPa from a raw pressure reading, whichever unit the glove reports. A glove at rest reads near 0 in gauge kPa and near 100000 in absolute pascals.
- **`static looks_like_absolute_pa(raw_values: PackedFloat32Array) -> bool`** — True if any reading looks like absolute pascals.
- **`static build_inbound(op: int, payload: PackedByteArray) -> PackedByteArray`** — Builds an inbound frame with its XOR checksum. For the simulated glove and tests.

---

# Hands

## HexRRig

*extends `Node3D` · `addons/hexr/hands/hexr_rig.gd`*

The HexR rig for a scene: both [`HexRTrackedHand`](#hexrtrackedhand)s and both [`PressureTrackerMain`](#pressuretrackermain)s. Put it under your `XROrigin3D`. Missing parts are created when the scene runs, so an empty HexRRig node is a complete rig; Project > Tools > HexR > Create HexR Rig adds them as nodes you can see and tune.

### Methods

- **`find_hand(hand: int) -> HexRTrackedHand`**
- **`find_controller(hand: int) -> PressureTrackerMain`**

## HexRTrackedHand

*extends `Node3D` · `addons/hexr/hands/hexr_tracked_hand.gd`*

One tracked hand: reads the OpenXR hand tracker and moves six [`HapticFingerTrigger`](#hapticfingertrigger)s (five fingertips and the palm) with its joints, and tracks how curled each finger is.

It reads `XRHandTracker` directly (the standard OpenXR joints), so it works on Meta Quest, PICO and any OpenXR runtime, with or without a hand mesh. Put it anywhere under the `XROrigin3D`; [`HexRRig`](#hexrrig) creates two.

### Signals

- **`tracking_changed(tracking: bool)`**

### Inspector properties

- **`hand: HaptGloveHandler.HandType = HaptGloveHandler.HandType.LEFT`**
- **`tracker_name: StringName = &""`** — Leave empty for the standard OpenXR tracker (/user/hand_tracker/left or /right).
- **`tip_radius := 0.008`**
- **`tip_offsets: Array[Vector3] = []`** — Per finger, Thumb..Pinky. Empty uses the defaults for this hand.
- **`palm_size := Vector3(0.062, 0.0203, 0.0605)`**
- **`palm_offset := Vector3(0.001, -0.0193, 0.0038)`**
- **`touch_layer: int = 1 << 19`** — Physics layer of the touch points. Zones and components must include it in their mask.
- **`show_touch_points := false`** — Draw the touch points (for checking placement).

### Properties

- **`touch_points: Array[HapticFingerTrigger] = []`** — The six touch points, indexed by `Haptics.Finger`.
- **`finger_use := FingerUseTracking.new()`**
- **`tracking := false`** — True while the tracker reports this hand.

### Methods

- **`get_tracker_name() -> StringName`**
- **`get_tracker() -> XRHandTracker`**
- **`touch_point(finger: int) -> HapticFingerTrigger`**
- **`get_joint_global_transform(joint: int) -> Transform3D`** — A joint's global transform this frame, or null-equivalent identity when it is not tracked. `joint` is an `XRHandTracker.HandJoint`.
- **`is_joint_valid(joint: int) -> bool`**
- **`update_from_tracker() -> void`** — Moves the touch points to the tracker's current joints. Called every physics frame.

### Constants

- **`KNUCKLE_JOINTS: Array[int] = …`** — Where each finger's curl is measured from (the thumb from its metacarpal).
- **`DEFAULT_TIP_OFFSETS_LEFT: Array[Vector3] = …`** — Fingertip sphere centres in joint space (OpenXR: -Z toward the tip, -Y toward the palm): a few millimetres toward the pad and back from the tip. The Unity package's values for the same OpenXR joints, tuned on PICO, with Z flipped from Unity's left-handed axes.

## HapticFingerTrigger

*extends `Area3D` · `addons/hexr/hands/haptic_finger_trigger.gd`*

A fingertip or the palm of a tracked hand (port of the Unity package's HapticFingerTrigger). [`HexRTrackedHand`](#hexrtrackedhand) creates six of them and moves them with the hand's joints. Zones and components find out which finger touched them from the touch point that entered them:

```gdscript
func _on_area_entered(area: Area3D) -> void:
    if area is HapticFingerTrigger:
        area.trigger_fix_pressure(0.6)
```

### Inspector properties

- **`hand: HaptGloveHandler.HandType = HaptGloveHandler.HandType.LEFT`**
- **`finger: Haptics.Finger = Haptics.Finger.INDEX`**

### Methods

- **`controller() -> PressureTrackerMain`**
- **`glove() -> HaptGloveHandler`**
- **`is_palm() -> bool`**
- **`trigger_fix_pressure(intensity: float) -> void`** — Presses this finger, skipping the hand-near check (the touch is the evidence).
- **`trigger_vibration_pressure(frequency: float, intensity: float) -> void`** — Vibrates this finger. `frequency` 0.1..40 Hz.
- **`remove_vibration() -> void`**
- **`remove_haptics() -> void`**

## FingerUseTracking

*extends `RefCounted` · `addons/hexr/hands/finger_use_tracking.gd`*

How curled each finger is, from 0 (fully curled) to 1 (fully extended). Port of the Unity package's FingerUseTracking: each finger's tip-to-knuckle distance, normalised against the smallest and largest seen so far, so it calibrates itself as the wearer moves their hand. Reach it as `HexR.tracked_hand(hand).finger_use`.

### Properties

- **`thumb_use := 0.0`**
- **`index_use := 0.0`**
- **`middle_use := 0.0`**
- **`ring_use := 0.0`**
- **`little_use := 0.0`**

### Methods

- **`update(distances: PackedFloat32Array) -> void`** — Feeds this frame's tip-to-knuckle distances, Thumb..Pinky.
- **`get_use(finger: int) -> float`** — The use of `finger` (Thumb..Pinky); the palm has none.
- **`is_hand_open() -> bool`** — Every finger extended: what releases a [`HexRGrabbable`](#hexrgrabbable).
- **`reset_calibration() -> void`**

---

# Haptics

## PressureTrackerMain

*extends `Node` · `addons/hexr/haptics/pressure_tracker_main.gd`*

A hand's "Pressure Controller" (port of the Unity package's PressureTrackerMain). Every haptic for that hand goes through here; a hand without one produces no haptics. Reach it as `HexR.controller(HaptGloveHandler.HandType.LEFT)`.

Calls other than the `remove_*` ones only fire while the hand is near something: grabbing, poke-hovering, or touching a [`ProximityCheck`](#proximitycheck) (the "hand-near check"). Pass `bypass_hand_check` to the custom calls to skip it.

Intensity is 0.1..1 (about 15..50 kPa). Components use a 10..60 strength scale; convert with `strength_to_intensity()`.

### Inspector properties

- **`hand: HaptGloveHandler.HandType = HaptGloveHandler.HandType.LEFT`**

### Properties

- **`hand_grabbing := false`** — Set by grab interactions (HexRGrabbable, the XR Tools binding).
- **`poke_hovering := false`** — Set by poke interactions.

### Methods

- **`static strength_to_intensity(strength: float) -> float`** — Unity StrengthToIntensity: the 10..60 component scale to 0.1..1 intensity.
- **`glove() -> HaptGloveHandler`** — This hand's glove, or null.
- **`tracked_hand() -> HexRTrackedHand`** — This hand's tracked hand (joints, touch points, finger curl), or null.
- **`hand_grabbing_check(is_grabbing: bool) -> void`**
- **`poke_hovering_check(is_hovering: bool) -> void`**
- **`is_physics_collision_near(near: bool) -> void`** — Sets the physics-contact flag directly (Unity IsPhysicsCollisionNear).
- **`set_near_source(source: Object, near: bool) -> void`** — Proximity zones report here; the hand counts as near while any of them says so.
- **`collision_near() -> bool`**
- **`is_hand_near() -> bool`**
- **`single_thumb_haptic(intensity: float) -> void`**
- **`single_index_haptic(intensity: float) -> void`**
- **`single_middle_haptic(intensity: float) -> void`**
- **`single_ring_haptic(intensity: float) -> void`**
- **`single_pinky_haptic(intensity: float) -> void`**
- **`single_palm_haptic(intensity: float) -> void`**
- **`remove_thumb_haptics() -> void`**
- **`remove_index_haptics() -> void`**
- **`remove_middle_haptics() -> void`**
- **`remove_ring_haptics() -> void`**
- **`remove_pinky_haptics() -> void`**
- **`remove_palm_haptics() -> void`**
- **`custom_single_haptics(finger: int, on: bool, intensity: float, speed: float = 1.0, bypass_hand_check: bool = false) -> void`** — Pressure on one channel. `on` false releases it.
- **`custom_single_vibrations(finger: int, on: bool, intensity: float, frequency: float, bypass_hand_check: bool = false) -> void`** — Vibration on one channel. `frequency` 0.1..40 Hz.
- **`trigger_all_haptics_increase(intensity: float) -> void`**
- **`trigger_custom_haptics_increase(fingers_on: Array, intensity: float, speed: float = 1.0) -> void`** — `fingers_on`: six booleans, Thumb..Palm. A false entry releases that channel.
- **`trigger_pinch_pressure(intensity: float) -> void`**
- **`remove_pinch_pressure() -> void`**
- **`trigger_all_vibrations(frequency: float) -> void`** — Every channel vibrating at `frequency` Hz, at half intensity.
- **`trigger_custom_vibrations(fingers_on: Array, intensity: float, frequency: float) -> void`**
- **`remove_all_haptics() -> void`** — Releases every channel's pressure. Not gated by the hand-near check.
- **`remove_all_vibrations() -> void`** — Stops every channel's vibration. Not gated by the hand-near check.
- **`trigger_pulse_all(intensity: float = 0.3) -> void`** — One short pulse on every channel. Replaces the Unity package's TriggerPulseIt, which used a deprecated command.
- **`get_pressures_kpa() -> PackedFloat32Array`** — The glove's pressure readings in gauge kPa (Thumb..Palm, then the air source).

---

# Scene nodes

## HexRGrabbable

*extends `Area3D` · `addons/hexr/components/hexr_grabbable.gd`*

Grab with a glove hand, no interaction toolkit needed (port of the Unity package's HexRGrabbable). Make it a child of the object to grab (usually a `RigidBody3D`) and give it a collision shape a little larger than the object.

A pinch grab holds while the thumb and any other finger touch; a palm grab while the palm and any finger touch. Each touching finger is pressed at `haptic_strength`. The object is let go when the hand opens (after a short grace), when only the anchor (thumb or palm) still touches, or when the anchor has lost contact.

### Signals

- **`grabbed(hand: int)`**
- **`released(hand: int)`**

### Inspector properties

- **`grab_type: GrabType = GrabType.PINCH`**
- **`target: Node3D`** — The object that moves. Empty uses the parent.
- **`gravity_on_release := true`** — Gravity on the object after it is let go (for a RigidBody3D).
- **`haptic_strength := 10.0`** — How firmly each touching finger is pressed: 10 barely there, 60 firm, 0 no haptics.
- **`open_hand_grace := 0.5`** — Seconds after grabbing before an open hand lets go.
- **`lost_contact_grace := 0.2`** — Seconds the anchor may lose contact before the object is let go.

### Methods

- **`is_grabbed() -> bool`**
- **`grabbing_hand() -> int`** — The hand holding the object, or -1.

### Enums

- **`GrabType { PINCH, PALM }`**

## HexRPhysicalButton

*extends `Area3D` · `addons/hexr/components/hexr_physical_button.gd`*

A button pressed by a fingertip, with no interaction toolkit needed. The pressing finger feels it for as long as it stays in. Size the collision shape to the button's face.

### Signals

- **`pressed`**
- **`released`**

### Inspector properties

- **`fingers: int = 2`** — Which fingers can press it. Index only is the predictable choice: a palm or a curled ring finger brushing past should not fire it.
- **`cap: Node3D`** — The part that visibly moves. Empty moves this node itself.
- **`travel := 0.006`** — How far the cap sinks, in metres, along `press_direction`.
- **`press_direction := Vector3.DOWN`** — Local direction the cap moves when pressed.
- **`press_pressure := 40.0`** — Pressure on the pressing finger while held: 10 barely there, 60 firm, 0 off.
- **`rearm_seconds := 0.2`** — Ignore a new press for this long after one ends, so a finger resting on the edge cannot chatter the button.

### Methods

- **`is_pressed() -> bool`**
- **`accepts(finger: int) -> bool`**

## SpecialHaptics

*extends `Area3D` · `addons/hexr/components/special_haptics.gd`*

A zone with a ready-made haptic effect for the fingers inside it (port of the Unity package's SpecialHaptics). Effects skip the hand-near check: being in the zone is enough.

- Custom vibrations: touching fingers vibrate at `vibration_frequency`.
- Custom haptics: touching fingers press at `haptic_pressure` (10..60).
- Fountain: touching fingers vibrate at 18 Hz, as if under running water.
- Rain drop: the palm gets random patterns of drops.
- Heart beat: touching fingers pulse like a pulse point, regular or irregular.
- Hand squeeze: emits `squeezed` when a hand closes around the zone.

### Signals

- **`squeezed(hand: int)`**

### Inspector properties

- **`effect: Effect = Effect.CUSTOM_HAPTICS`**
- **`haptic_strength := 0.5`** — Intensity (0.1..1) for custom vibrations and rain drops.
- **`vibration_frequency := 1.0`** — Custom vibrations frequency in Hz.
- **`haptic_pressure := 10.0`** — Custom haptics pressure on the 10..60 strength scale.
- **`heart_beat_pressure := 0.5`** — Intensity (0.1..1) of each beat.
- **`heart_beat: HeartBeat = HeartBeat.REGULAR`**
- **`in_timer := 0.4`** — Seconds each beat presses, then rests (regular beats).
- **`out_timer := 0.3`**
- **`include_palm := false`** — Let the palm feel the beat too.
- **`squeeze_tightness := 0.2`** — The squeeze fires when a finger enters the zone while every finger's use (0 curled .. 1 extended) is at least this value. The Unity package's rule, kept as is.

### Methods

- **`toggle_heart_regularity() -> void`** — Switches the heart beat between regular and irregular.

### Enums

- **`Effect { CUSTOM_VIBRATIONS, CUSTOM_HAPTICS, FOUNTAIN, RAIN_DROP, HEART_BEAT, HAND_SQUEEZE }`**
- **`HeartBeat { REGULAR, IRREGULAR }`**

## HexRUsable

*extends `Area3D` · `addons/hexr/components/hexr_usable.gd`*

Fires when a hand touching this area curls the chosen fingers, and again when it lets them out (port of the Unity package's HexRUsable): squeeze a spray can, pull a trigger.

The Unity component only looked at the last finger it checked; this one needs every chosen finger past the threshold.

### Signals

- **`used(hand: int)`**
- **`stopped_using(hand: int)`**

### Inspector properties

- **`fingers: int = 2`** — The fingers that have to curl.
- **`use_threshold := 0.3`** — 0 is fully curled, 1 fully extended. A finger counts as curled below this.

### Methods

- **`is_in_use() -> bool`**

## ProximityCheck

*extends `Area3D` · `addons/hexr/components/proximity_check.gd`*

Marks a hand as "near" while any of its touch points is inside this area, which opens the hand-near check on that hand's [`PressureTrackerMain`](#pressuretrackermain). Use it around objects whose haptics come from code or from an interaction toolkit that does not report grabs itself. Size the collision shape to the space a hand has to be in.

### Inspector properties

- **`clear_delay := 0.5`** — How long a hand still counts as near after its last contact.

### Methods

- **`is_near(hand: int) -> bool`** — True while `hand` counts as near this zone.

## HexRInteractableHaptics

*extends `Node` · `addons/hexr/interaction/hexr_interactable_haptics.gd`*

Haptics for an object picked up through an interaction toolkit (port of the Unity package's HexRInteractableHaptics). The recommended way to make an existing grabbable object felt.

Make it a child of a Godot XR Tools `XRToolsPickable` and it binds itself: the chosen fingers press while the object is held (or hovered, see `fire_on`). For other toolkits, call `set_interactor_state()` from their signals.

With `follow_grip`, pressure follows how tightly the hand is closed, between `min_strength` and `strength`: squeeze harder, feel more.

### Inspector properties

- **`fire_on: FireOn = FireOn.SELECT`**
- **`thumb := true`**
- **`index := true`**
- **`middle := true`**
- **`ring := false`**
- **`pinky := false`**
- **`palm := true`**
- **`strength := 30.0`** — 10 (lightest) to 60 (firm). 30 suits a small prop, 40 something heavier. Below 5, nothing.
- **`follow_grip := true`**
- **`min_strength := 10.0`**
- **`auto_bind_xr_tools := true`** — Find an XR Tools pickable on the parent and follow its pick-up and highlight signals.

### Methods

- **`bound_to() -> String`** — What the binding is attached to, for diagnostics.
- **`set_interactor_state(interactor_key: Variant, hand: int, hovering: bool, selecting: bool) -> void`** — Reports what one interactor (a hand, a ray, a controller) is doing with this object. `hand` is `HaptGloveHandler.HandType`, or -1 when the toolkit cannot tell.
- **`clear_interactor(interactor_key: Variant) -> void`**

### Enums

- **`FireOn { SELECT, HOVER, SELECT_AND_HOVER }`**

## HexRXRToolsBinding

*extends `RefCounted` · `addons/hexr/interaction/hexr_xr_tools_binding.gd`*

Connects a Godot XR Tools pickable to a [`HexRInteractableHaptics`](#hexrinteractablehaptics). Duck-typed: the addon does not need XR Tools installed, and nothing here runs unless the object has its signals.

Picking up marks the hand as grabbing on its Pressure Controller (opening the hand-near check) and reports "selecting"; a highlight reports "hovering" for the hand of the nearest pickup.

### Methods

- **`static bind(start: Node, sink: HexRInteractableHaptics) -> HexRXRToolsBinding`** — Binds `start` (or its nearest ancestor with a picked_up signal). Returns null if there is nothing to bind to.
- **`describe() -> String`**

---

# Menu and HexR Remote

## HexRFloatingMenu

*extends `Node3D` · `addons/hexr/ui/hexr_floating_menu.gd`*

The HexR menu as a panel in the room (port of the Unity package's HexRFloatingMenu): press its buttons with a fingertip, move it by pinching its header. It stays where it is put, and does not follow the head; call `recenter()` to bring it in front of the wearer.

Each press gives the pressing finger a short tap.

### Inspector properties

- **`panel_width := 0.26`** — Panel width in metres.
- **`show_haptics_readout := true`**
- **`scenes: PackedStringArray = []`** — Scene paths offered on the panel. Empty hides the section.
- **`spawn_distance := 0.65`** — Where `recenter()` puts the panel, relative to the head.
- **`spawn_height_offset := -0.2`**
- **`spawn_side_offset := -0.35`**
- **`recenter_on_start := false`** — Bring the panel in front of the wearer when the scene starts.

### Properties

- **`panel: HexRMenuPanel`**

### Methods

- **`recenter() -> void`** — Puts the panel in front of the wearer's head, facing them.

## HexRRemote

*extends `Node` · `addons/hexr/remote/hexr_remote.gd`*

HexR Remote: lets a phone running the HexR Companion (Headsets tab) find this app on the local Wi-Fi, connect and release its gloves, read their state, switch scenes, run commands, and watch the headset's view and sound. Port of the Unity package's HexRRemote, speaking the same protocol (docs/RemoteProtocol.md), so the same phone app works with both.

Add one to the first scene (Project > Tools > HexR > Add HexR Remote). It is local-network only and not authenticated: anyone on the same Wi-Fi with a HexR Remote client can control the gloves. Bring a dedicated router to events.

```gdscript
HexRRemote.register_command("reset", "Reset demo", reset_demo)
```

### Inspector properties

- **`allow_glove_control := true`** — Connect and disconnect the gloves, and release their haptics.
- **`allow_video := true`** — Share the headset view. The wearer still has to accept Android's prompt each session.
- **`expose_scenes := false`** — Show the phone `scenes` and let it switch between them.
- **`scenes: Array[String] = []`** — The scenes a phone can switch to, in order.
- **`video_width := 1024`** — Encoded size, rounded to a multiple of 16. Quest's compositor delivers a square view.
- **`video_height := 1024`**
- **`video_bitrate_kbps := 4000`**
- **`video_fps := 30`**
- **`stop_video_after_background_seconds := 20`** — End sharing if the app stays in the background this long.
- **`share_sound := true`** — Share the app's own sound with its view. Android guards any audio capture with the microphone permission, so the wearer is asked for it once; the build gets that permission only while a Remote shares sound.
- **`discovery_port := HexRRemoteProtocol.DEFAULT_DISCOVERY_PORT`**
- **`control_port := HexRRemoteProtocol.DEFAULT_CONTROL_PORT`** — If taken, the next free port is used and announced.
- **`video_port := HexRRemoteProtocol.DEFAULT_VIDEO_PORT`**
- **`audio_port := HexRRemoteProtocol.DEFAULT_AUDIO_PORT`**
- **`status_per_second := 5.0`**

### Properties

- **`static instance: HexRRemote`**
- **`announce_address := "255.255.255.255"`** — Where the announcement is sent (tests set 127.0.0.1).

### Methods

- **`static register_command(id: String, label: String, action: Callable) -> void`** — Lets a phone run `action` by `id`; it is listed by `label`.
- **`static unregister_command(id: String) -> void`**
- **`static has_command(id: String) -> bool`**
- **`static get_command(id: String) -> Callable`** — The command's action, or an invalid Callable (unknown id, or its object was freed).
- **`static command_list() -> Array`**
- **`is_running() -> bool`**
- **`get_control_port() -> int`** — The control port in use (it moves up if the preferred one is taken).
- **`phones_connected() -> int`**
- **`begin() -> void`**
- **`shutdown() -> void`**
- **`clock_us() -> int`** — Microseconds on the clock the video and sound are stamped with (CLOCK_MONOTONIC on Android).

### Constants

- **`HEXR_VERSION := HexRManager.PROTOCOL_VERSION`** — The Unity package version this matches: what phones check before offering features.

---

# Internals

Used by the classes above; most games never touch them. Their doc comments are in the
source and in Godot's built-in help.

| Class | File | What it is |
|---|---|---|
| `HexRAndroidTransport` | `addons/hexr/transport/hexr_android_transport.gd` | Bluetooth through the HexRBle Android plugin (addons/hexr/android/bin/hexr-ble-*.aar). |
| `HexRBleTransport` | `addons/hexr/transport/hexr_ble_transport.gd` | The Bluetooth LE link to the gloves. |
| `HexRDeviceStore` | `addons/hexr/core/hexr_device_store.gd` | Remembers which physical glove each hand uses, so a reconnect skips the scan and a second glove for the same hand in range is not picked by mistake. |
| `HexRF32` | `addons/hexr/core/hexr_f32.gd` | 32-bit float arithmetic for the glove encoder. |
| `HexRFrames` | `addons/hexr/core/hexr_frames.gd` | Splitting concatenated outbound frames. |
| `HexRMenuPanel` | `addons/hexr/ui/hexr_menu_panel.gd` | The HexR menu's 2D content: glove connection, battery and pump, a live haptics readout, and a few tools. |
| `HexRRemoteCommands` | `addons/hexr/remote/hexr_remote_commands.gd` | Runs a phone's requests against the gloves and the app (port of the Unity package's RemoteCommands). |
| `HexRRemoteHaptics` | `addons/hexr/remote/hexr_remote_haptics.gd` | The haptics lines HexR Remote sends: what each glove channel was told to do, whenever it changes (port of the Unity package's RemoteHaptics). |
| `HexRRemoteProtocol` | `addons/hexr/remote/hexr_remote_protocol.gd` | HexR Remote protocol, version 1: the messages a phone (the HexR Companion's Headsets tab) and a headset exchange. |
| `HexRRemoteServer` | `addons/hexr/remote/hexr_remote_server.gd` | HexR Remote's network side (port of the Unity package's RemoteServer and RemoteDiscovery): the TCP control port phones connect to, and the UDP announcement they find it by. |
| `HexRRemoteStream` | `addons/hexr/remote/hexr_remote_stream.gd` | Sharing the headset's view and sound with HexR Remote viewers. |
| `HexRSimulatedGlove` | `addons/hexr/transport/hexr_simulated_glove.gd` | A software glove that behaves like the firmware, for tests and for working without hardware. |
| `HexRSimulatedTransport` | `addons/hexr/transport/hexr_simulated_transport.gd` | A transport with simulated gloves instead of a radio. |
| `HexRTlv` | `addons/hexr/core/hexr_tlv.gd` | Type-length-value field encoder for glove frames (port of Encode.cs). |
| `HexRWindowsTransport` | `addons/hexr/transport/hexr_windows_transport.gd` | Bluetooth through the HexRBleWinRT GDExtension (addons/hexr/bin/windows). |
| `HexRWriteCoalescer` | `addons/hexr/core/hexr_write_coalescer.gd` | Batches haptic commands into at most one Bluetooth write per interval. |

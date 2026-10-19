# Changelog

The HexR Godot addon. Versions follow semver; the HexR Remote protocol level it speaks is
`HexRManager.PROTOCOL_VERSION` (the Unity package version it matches).

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

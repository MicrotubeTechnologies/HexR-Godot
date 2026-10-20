# HexR tutorial content

Scripts from the HexR Godot tutorial, imported by **HexR > Import Tutorial Content** (the Godot
counterpart of the Unity package's *Tutorial Content* sample). The full scenes they come from
are in the tutorial project: https://github.com/MicrotubeTechnologies/HexR-Developer-Tutorial-Godot

| Script | Attach to | What it does |
|---|---|---|
| `lightbulb.gd` | A `MeshInstance3D` | A bulb a `HexRPhysicalButton`'s `pressed` signal switches with `toggle()` |
| `squeezing_heart.gd` | A `Node3D` holding a heart mesh | Beats harder for a few seconds when its hand-squeeze zone fires |
| `heartbeat_toggle.gd` | Any node | Switches every heart-beat zone between a regular and an irregular beat; also a HexR Remote command |
| `flame.gd` | An `OmniLight3D` | A flickering torch flame |

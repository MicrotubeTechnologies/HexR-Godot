# Third-party notices

The HexR Godot addon is released under the MIT License (see [LICENSE](LICENSE)). It includes or
is built with the following.

## godot-cpp (MIT)

Compiled into the HexRBleWinRT extension libraries (`addons/hexr/bin/`).
Copyright (c) 2017-present Godot Engine contributors; Copyright (c) 2014-2017 Juan Linietsky,
Ariel Manzur. https://github.com/godotengine/godot-cpp

## C++/WinRT (MIT)

Header-only projection from the Windows SDK, compiled into the Windows extension library.
Copyright (c) Microsoft Corporation. https://github.com/microsoft/cppwinrt

## BleWinrtDll (WTFPL), design reference

The Windows extension is new code, but its approach follows adabru/BleWinrtDll, which the HexR
Unity package ships as a binary. https://github.com/adabru/BleWinrtDll. Note: the Unity
package's notice lists BleWinrtDll as MIT; upstream's licence file is the WTFPL.

## HexR Remote capture (MIT, Microtube Technologies)

`android_plugin/hexr-remote/src/main/java/com/microtube/hexr/remote/` is copied unchanged from
the HexR Unity package (com.microtube.hexr), under the same MIT licence as this addon.

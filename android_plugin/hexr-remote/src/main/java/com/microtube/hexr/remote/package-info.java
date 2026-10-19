/**
 * HexR Remote's screen and sound capture: MediaProjection into an H.264 encoder, the app's own
 * audio into AAC, and the TCP stream servers HexR Remote viewers connect to.
 *
 * Copied unchanged from the Unity package (com.microtube.hexr, Runtime/Plugins/Android/HexRRemote,
 * MIT, Microtube Technologies). Keep the files identical so a fix in either package can be
 * diffed straight across. The Godot side reaches this code through
 * com.microtube.hexr.godot.remote.HexRRemoteCapturePlugin.
 */
package com.microtube.hexr.remote;

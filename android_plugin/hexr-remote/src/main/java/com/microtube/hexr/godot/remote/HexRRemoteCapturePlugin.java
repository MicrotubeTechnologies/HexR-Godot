package com.microtube.hexr.godot.remote;

import com.microtube.hexr.remote.HexRScreenCapture;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * The HexRRemoteCapture engine singleton: HexR Remote's live view and sound on Android.
 * A thin bridge to HexRScreenCapture, making the same calls the Unity package's RemoteStream.cs
 * makes. GDScript reaches it through addons/hexr/remote/remote_stream.gd.
 */
public class HexRRemoteCapturePlugin extends GodotPlugin {
    public HexRRemoteCapturePlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "HexRRemoteCapture";
    }

    /** Asks the wearer to allow screen sharing, then streams. See HexRScreenCapture.start. */
    @UsedByGodot
    public void start(int width, int height, int bitrateKbps, int fps, int videoPort,
                      boolean shareSound, int soundPort, int stopAfterBackgroundSeconds) {
        HexRScreenCapture.start(getActivity(), width, height, bitrateKbps, fps, videoPort,
                shareSound, soundPort, stopAfterBackgroundSeconds);
    }

    @UsedByGodot
    public void stop() {
        HexRScreenCapture.stop();
    }

    @UsedByGodot
    public String getState() {
        return HexRScreenCapture.getState();
    }

    @UsedByGodot
    public String getMessage() {
        return HexRScreenCapture.getMessage();
    }

    @UsedByGodot
    public int getPort() {
        return HexRScreenCapture.getPort();
    }

    @UsedByGodot
    public int getWidth() {
        return HexRScreenCapture.getWidth();
    }

    @UsedByGodot
    public int getHeight() {
        return HexRScreenCapture.getHeight();
    }

    @UsedByGodot
    public int getViewerCount() {
        return HexRScreenCapture.getViewerCount();
    }

    @UsedByGodot
    public String getSoundState() {
        return HexRScreenCapture.getSoundState();
    }

    @UsedByGodot
    public String getSoundMessage() {
        return HexRScreenCapture.getSoundMessage();
    }

    @UsedByGodot
    public int getSoundPort() {
        return HexRScreenCapture.getSoundPort();
    }

    @UsedByGodot
    public int getSoundSampleRate() {
        return HexRScreenCapture.getSoundSampleRate();
    }

    @UsedByGodot
    public int getSoundChannels() {
        return HexRScreenCapture.getSoundChannels();
    }
}

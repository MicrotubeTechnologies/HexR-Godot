package com.microtube.hexr.godot.ble;

import android.app.Activity;
import android.content.Context;
import android.os.BatteryManager;
import android.os.Build;
import android.provider.Settings;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;

/**
 * The HexRBle engine singleton: Bluetooth LE for HexR gloves on Android headsets.
 * GDScript reaches it through HexRAndroidTransport; nothing here is meant to be called directly.
 *
 * Signals are emitted from Android threads and delivered by Godot on its main loop thread.
 */
public class HexRBlePlugin extends GodotPlugin implements BleEngine.Listener {
    private static final int PERMISSION_REQUEST = 0x4858; // "HX"

    private static final SignalInfo DEVICE_FOUND = new SignalInfo("device_found", String.class, String.class, Integer.class);
    private static final SignalInfo SCAN_FINISHED = new SignalInfo("scan_finished", String.class);
    private static final SignalInfo CONNECTED = new SignalInfo("connected", String.class, Integer.class);
    private static final SignalInfo CONNECT_FAILED = new SignalInfo("connect_failed", String.class, String.class);
    private static final SignalInfo DISCONNECTED = new SignalInfo("disconnected", String.class, String.class);
    private static final SignalInfo NOTIFIED = new SignalInfo("notified", String.class, byte[].class);
    private static final SignalInfo PERMISSIONS_RESULT = new SignalInfo("permissions_result", Boolean.class);

    private BleEngine engine;
    private volatile boolean paused;

    public HexRBlePlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "HexRBle";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(DEVICE_FOUND);
        signals.add(SCAN_FINISHED);
        signals.add(CONNECTED);
        signals.add(CONNECT_FAILED);
        signals.add(DISCONNECTED);
        signals.add(NOTIFIED);
        signals.add(PERMISSIONS_RESULT);
        return signals;
    }

    private BleEngine engine() {
        if (engine == null) {
            Context c = getContext();
            engine = new BleEngine(c, this);
        }
        return engine;
    }

    // -- BleEngine.Listener ---------------------------------------------------------------

    @Override
    public void onDeviceFound(String id, String name, int rssi) {
        emitSignal(DEVICE_FOUND, id, name, rssi);
    }

    @Override
    public void onScanFinished(String error) {
        emitSignal(SCAN_FINISHED, error);
    }

    @Override
    public void onConnected(String id, int mtu) {
        emitSignal(CONNECTED, id, mtu);
    }

    @Override
    public void onConnectFailed(String id, String reason) {
        emitSignal(CONNECT_FAILED, id, reason);
    }

    @Override
    public void onDisconnected(String id, String reason) {
        emitSignal(DISCONNECTED, id, reason);
    }

    @Override
    public void onNotified(String id, byte[] data) {
        emitSignal(NOTIFIED, id, data);
    }

    // -- methods for GDScript -------------------------------------------------------------

    @UsedByGodot
    public boolean isAdapterEnabled() {
        return engine().isAdapterEnabled();
    }

    @UsedByGodot
    public boolean hasPermissions() {
        return engine().hasPermissions();
    }

    @UsedByGodot
    public void requestPermissions() {
        Activity activity = getActivity();
        if (engine().hasPermissions() || activity == null) {
            emitSignal(PERMISSIONS_RESULT, engine().hasPermissions());
            return;
        }
        activity.runOnUiThread(() -> activity.requestPermissions(BleEngine.requiredPermissions(), PERMISSION_REQUEST));
    }

    @Override
    public void onMainRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode == PERMISSION_REQUEST) {
            emitSignal(PERMISSIONS_RESULT, engine().hasPermissions());
        }
    }

    /** Why scanning would find nothing (Bluetooth off, no permission, Location off), or "". */
    @UsedByGodot
    public String getScanBlocker() {
        return engine().scanBlocker();
    }

    @UsedByGodot
    public void startScan(int timeoutMs) {
        engine().startScan(timeoutMs);
    }

    @UsedByGodot
    public void stopScan() {
        engine().stopScan();
    }

    @UsedByGodot
    public boolean isScanning() {
        return engine().isScanning();
    }

    @UsedByGodot
    public void connectDevice(String id) {
        engine().connect(id);
    }

    @UsedByGodot
    public void disconnectDevice(String id) {
        engine().disconnect(id);
    }

    @UsedByGodot
    public boolean isConnected(String id) {
        return engine().isConnected(id);
    }

    @UsedByGodot
    public boolean write(String id, byte[] data, boolean purge) {
        return engine().write(id, data, purge);
    }

    @UsedByGodot
    public int getMtu(String id) {
        return engine().getMtu(id);
    }

    /** Bytes written to this glove when the app is paused, since scripts stop running then. */
    @UsedByGodot
    public void setPauseReleaseFrame(String id, byte[] data) {
        engine().setPauseReleaseFrame(id, data);
    }

    @UsedByGodot
    public void setMinWriteGapMs(int ms) {
        engine().minWriteGapMs = Math.max(0, ms);
    }

    @UsedByGodot
    public void shutdown() {
        engine().shutdown();
    }

    // -- device facts for HexR Remote -----------------------------------------------------

    /** CLOCK_MONOTONIC in microseconds: the clock HexR Remote's video and sound timestamps use. */
    @UsedByGodot
    public long clockUs() {
        return System.nanoTime() / 1000L;
    }

    /** True between onPause and onResume. Readable from any thread while scripts are stopped. */
    @UsedByGodot
    public boolean isAppPaused() {
        return paused;
    }

    @UsedByGodot
    public int getApiLevel() {
        return Build.VERSION.SDK_INT;
    }

    @UsedByGodot
    public String getDeviceManufacturer() {
        return Build.MANUFACTURER;
    }

    @UsedByGodot
    public String getDeviceModel() {
        return Build.MODEL;
    }

    /** The name the owner gave the device, or "" if none is readable. */
    @UsedByGodot
    public String getDeviceName() {
        try {
            String name = Settings.Global.getString(getContext().getContentResolver(), Settings.Global.DEVICE_NAME);
            return name == null ? "" : name;
        } catch (RuntimeException e) {
            return "";
        }
    }

    /** Headset battery in percent, or -1. */
    @UsedByGodot
    public int getBatteryPct() {
        BatteryManager bm = (BatteryManager) getContext().getSystemService(Context.BATTERY_SERVICE);
        if (bm == null) {
            return -1;
        }
        int pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);
        return pct <= 0 || pct > 100 ? -1 : pct;
    }

    // -- lifecycle ------------------------------------------------------------------------

    @Override
    public void onMainPause() {
        paused = true;
        // Scripts stop running from here on, so the release has to come from this side.
        if (engine != null) {
            engine.onAppPaused();
        }
    }

    @Override
    public void onMainResume() {
        paused = false;
    }

    @Override
    public void onMainDestroy() {
        if (engine != null) {
            engine.shutdown();
        }
    }
}

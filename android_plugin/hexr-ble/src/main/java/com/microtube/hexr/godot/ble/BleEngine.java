package com.microtube.hexr.godot.ble;

import android.Manifest;
import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanRecord;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * GATT client for HexR gloves. Ported from the HexR Companion's BleEngine.kt, which runs the
 * same gloves in production.
 *
 * Rules the glove's firmware depends on:
 *   - subscribe to notifications exactly once per connection (each subscribe starts a timer
 *     on the glove, and a second one leaks it);
 *   - write with response, one write in flight, each write cut to fit MTU - 3 on frame
 *     boundaries (the firmware ignores long writes).
 *
 * All state lives on the main looper. Public methods may be called from any thread (Godot calls
 * from its render thread) and post their work there.
 */
@SuppressLint("MissingPermission")
final class BleEngine {
    static final String TAG = "HexRBle";

    static final UUID SERVICE_UUID = UUID.fromString("000000ff-0000-1000-8000-00805f9b34fb");
    static final UUID CHARACTERISTIC_UUID = UUID.fromString("0000ff01-0000-1000-8000-00805f9b34fb");
    static final UUID CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");

    /** Android stops answering a sixth scan start within 30 s; keep starts 6 s apart. */
    static final long MIN_SCAN_GAP_MS = 6_000L;
    static final long REPORT_EVERY_MS = 1_000L;
    static final int DESIRED_MTU = 512;
    static final int DEFAULT_MTU = 23;
    static final int ATT_OVERHEAD = 3;
    static final long MTU_TIMEOUT_MS = 2_000L;
    static final long CCCD_TIMEOUT_MS = 2_000L;
    static final long WRITE_TIMEOUT_MS = 2_000L;
    static final long CLOSE_TIMEOUT_MS = 2_500L;
    static final long CONNECT_TIMEOUT_MS = 15_000L;
    static final int MAX_WRITE_RETRIES = 5;

    interface Listener {
        void onDeviceFound(String id, String name, int rssi);

        void onScanFinished(String error);

        void onConnected(String id, int mtu);

        void onConnectFailed(String id, String reason);

        void onDisconnected(String id, String reason);

        void onNotified(String id, byte[] data);
    }

    private final Context context;
    private final Listener listener;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Map<String, Session> sessions = new ConcurrentHashMap<>();
    private final ArrayDeque<Session> connectQueue = new ArrayDeque<>();
    private Session connecting;

    private ScanCallback scanCallback;
    private Runnable pendingScanStart;
    private long lastScanStart = -MIN_SCAN_GAP_MS;
    private int scanGeneration;
    private volatile boolean scanning;

    volatile int minWriteGapMs = 0;

    BleEngine(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
    }

    private BluetoothAdapter adapter() {
        BluetoothManager manager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
        return manager == null ? null : manager.getAdapter();
    }

    boolean isAdapterEnabled() {
        BluetoothAdapter a = adapter();
        return a != null && a.isEnabled();
    }

    static String[] requiredPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return new String[] {Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT};
        }
        return new String[] {Manifest.permission.ACCESS_FINE_LOCATION};
    }

    boolean hasPermissions() {
        for (String p : requiredPermissions()) {
            if (context.checkSelfPermission(p) != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
        }
        return true;
    }

    /** Why a scan would find nothing, or "" if nothing is in the way. */
    String scanBlocker() {
        if (!isAdapterEnabled()) {
            return "Bluetooth is off";
        }
        if (!hasPermissions()) {
            return "Bluetooth permission not granted";
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            // Android 11 and older report no Bluetooth devices at all while Location is off.
            LocationManager lm = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
            if (lm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && !lm.isLocationEnabled()) {
                return "Turn on Location: this headset only finds Bluetooth devices with Location on";
            }
        }
        return "";
    }

    // -- scanning -------------------------------------------------------------------------

    boolean isScanning() {
        return scanning;
    }

    void startScan(long timeoutMs) {
        scanning = true;
        handler.post(() -> startScanOnMain(timeoutMs));
    }

    private void startScanOnMain(long timeoutMs) {
        if (scanCallback != null || pendingScanStart != null) {
            return;
        }
        long wait = lastScanStart + MIN_SCAN_GAP_MS - SystemClock.elapsedRealtime();
        if (wait > 0) {
            pendingScanStart = () -> {
                pendingScanStart = null;
                startScanOnMain(timeoutMs);
            };
            handler.postDelayed(pendingScanStart, wait);
            return;
        }
        String blocker = scanBlocker();
        BluetoothAdapter a = adapter();
        BluetoothLeScanner scanner = a == null ? null : a.getBluetoothLeScanner();
        if (!blocker.isEmpty() || scanner == null) {
            finishScan(blocker.isEmpty() ? "Bluetooth is off" : blocker);
            return;
        }
        final Map<String, Long> lastReport = new HashMap<>();
        ScanCallback cb = new ScanCallback() {
            @Override
            public void onScanResult(int callbackType, ScanResult result) {
                report(result);
            }

            @Override
            public void onBatchScanResults(List<ScanResult> results) {
                for (ScanResult r : results) {
                    report(r);
                }
            }

            @Override
            public void onScanFailed(int errorCode) {
                handler.post(() -> stopScanOnMain("Scan failed (code " + errorCode + ")"));
            }

            private void report(ScanResult result) {
                String name = null;
                ScanRecord record = result.getScanRecord();
                if (record != null) {
                    name = record.getDeviceName();
                }
                if (name == null) {
                    try {
                        name = result.getDevice().getName();
                    } catch (SecurityException ignored) {
                        // No CONNECT permission: the advertised name is all there is.
                    }
                }
                if (name == null || name.isEmpty()) {
                    return;
                }
                String address = result.getDevice().getAddress();
                long now = SystemClock.elapsedRealtime();
                synchronized (lastReport) {
                    Long last = lastReport.get(address);
                    if (last != null && now - last < REPORT_EVERY_MS) {
                        return;
                    }
                    lastReport.put(address, now);
                }
                listener.onDeviceFound(address, name, result.getRssi());
            }
        };
        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build();
        try {
            scanner.startScan(null, settings, cb);
        } catch (RuntimeException e) {
            finishScan(e.getMessage() == null ? e.toString() : e.getMessage());
            return;
        }
        scanCallback = cb;
        lastScanStart = SystemClock.elapsedRealtime();
        final int generation = ++scanGeneration;
        handler.postDelayed(() -> {
            if (generation == scanGeneration && scanCallback == cb) {
                stopScanOnMain("");
            }
        }, Math.max(1_000L, timeoutMs));
        Log.d(TAG, "scan started");
    }

    void stopScan() {
        handler.post(() -> {
            if (pendingScanStart != null) {
                handler.removeCallbacks(pendingScanStart);
                pendingScanStart = null;
                finishScan("");
            } else if (scanCallback != null) {
                stopScanOnMain("");
            }
        });
    }

    private void stopScanOnMain(String error) {
        ScanCallback cb = scanCallback;
        if (cb == null) {
            return;
        }
        scanCallback = null;
        scanGeneration++;
        try {
            BluetoothAdapter a = adapter();
            if (a != null && a.getBluetoothLeScanner() != null) {
                a.getBluetoothLeScanner().stopScan(cb);
            }
        } catch (RuntimeException e) {
            Log.w(TAG, "stopScan: " + e);
        }
        finishScan(error);
    }

    private void finishScan(String error) {
        scanning = false;
        listener.onScanFinished(error);
    }

    // -- connections ----------------------------------------------------------------------

    boolean isConnected(String address) {
        Session s = sessions.get(address);
        return s != null && s.ready;
    }

    int getMtu(String address) {
        Session s = sessions.get(address);
        return s != null && s.ready ? s.mtu : 0;
    }

    void connect(String address) {
        handler.post(() -> {
            Session existing = sessions.get(address);
            if (existing != null) {
                if (existing.ready) {
                    listener.onConnected(address, existing.mtu);
                }
                return;
            }
            if (!hasPermissions()) {
                listener.onConnectFailed(address, "Bluetooth permission not granted");
                return;
            }
            BluetoothDevice device;
            try {
                device = adapter().getRemoteDevice(address);
            } catch (RuntimeException e) {
                listener.onConnectFailed(address, "Not a Bluetooth address: " + address);
                return;
            }
            Session s = new Session(address, device);
            sessions.put(address, s);
            connectQueue.add(s);
            pumpConnects();
        });
    }

    /** One connectGatt at a time: overlapping connects are the usual cause of GATT error 133. */
    private void pumpConnects() {
        if (connecting != null) {
            return;
        }
        Session next = connectQueue.poll();
        if (next == null) {
            return;
        }
        connecting = next;
        next.start();
    }

    private void connectSettled(Session s) {
        connectQueue.remove(s);
        if (connecting == s) {
            connecting = null;
            pumpConnects();
        }
    }

    void disconnect(String address) {
        handler.post(() -> {
            Session s = sessions.get(address);
            if (s != null) {
                s.close();
            }
        });
    }

    /** Returns false if the device is not connected. */
    boolean write(String address, byte[] data, boolean purge) {
        Session s = sessions.get(address);
        if (s == null || !s.ready || data == null || data.length == 0) {
            return false;
        }
        handler.post(() -> s.enqueue(data, purge));
        return true;
    }

    void setPauseReleaseFrame(String address, byte[] data) {
        Session s = sessions.get(address);
        if (s != null) {
            s.pauseFrame = data == null ? new byte[0] : data;
        }
    }

    /** The app is going to the background: release every glove that asked for it. */
    void onAppPaused() {
        handler.post(() -> {
            for (Session s : sessions.values()) {
                if (s.ready && s.pauseFrame.length > 0) {
                    s.enqueue(s.pauseFrame, true);
                }
            }
        });
    }

    void shutdown() {
        handler.post(() -> {
            stopScanOnMain("");
            for (Session s : sessions.values()) {
                if (s.ready && s.pauseFrame.length > 0) {
                    s.enqueue(s.pauseFrame, true);
                }
                s.close();
            }
        });
    }

    private final class Session extends BluetoothGattCallback {
        final String address;
        final BluetoothDevice device;
        volatile boolean ready;
        volatile int mtu = DEFAULT_MTU;
        volatile byte[] pauseFrame = new byte[0];

        private BluetoothGatt gatt;
        private BluetoothGattCharacteristic characteristic;
        private final ArrayDeque<byte[]> queue = new ArrayDeque<>();
        private boolean busy;
        private boolean closing;
        private boolean finished;
        private boolean linkUp;
        private boolean mtuSettled;
        private boolean cccdWritten;
        private int writeFailures;
        private long lastSendAt;

        private final Runnable writeTimeout = () -> {
            busy = false;
            pump();
        };
        private final Runnable forceClose = this::teardown;
        private final Runnable connectTimeout = () -> fail("timed out");
        private final Runnable cccdTimeout = this::markReady;

        Session(String address, BluetoothDevice device) {
            this.address = address;
            this.device = device;
        }

        void start() {
            Log.d(TAG, "connecting " + address);
            try {
                gatt = device.connectGatt(context, false, this, BluetoothDevice.TRANSPORT_LE);
            } catch (RuntimeException e) {
                gatt = null;
            }
            if (gatt == null) {
                fail("could not start a connection");
                return;
            }
            handler.postDelayed(connectTimeout, CONNECT_TIMEOUT_MS);
        }

        private void fail(String reason) {
            if (finished) {
                return;
            }
            Log.d(TAG, "connect failed " + address + ": " + reason);
            boolean asked = closing;
            teardown();
            if (!asked) {
                listener.onConnectFailed(address, reason);
            }
        }

        @Override
        public void onConnectionStateChange(BluetoothGatt g, int status, int newState) {
            handler.post(() -> {
                if (finished) {
                    return;
                }
                if (newState == BluetoothGatt.STATE_CONNECTED) {
                    linkUp = true;
                    try {
                        g.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
                    } catch (RuntimeException ignored) {
                        // Not fatal; the glove asks for 7.5 ms itself.
                    }
                    if (!g.requestMtu(DESIRED_MTU)) {
                        onMtuSettled(g, DEFAULT_MTU);
                    } else {
                        handler.postDelayed(() -> onMtuSettled(g, DEFAULT_MTU), MTU_TIMEOUT_MS);
                    }
                } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                    String why = status == BluetoothGatt.GATT_SUCCESS ? "disconnected" : "GATT error " + status;
                    boolean wasReady = ready;
                    boolean asked = closing;
                    teardown();
                    if (asked) {
                        return;
                    }
                    if (wasReady) {
                        listener.onDisconnected(address, why);
                    } else {
                        listener.onConnectFailed(address, why);
                    }
                }
            });
        }

        @Override
        public void onMtuChanged(BluetoothGatt g, int newMtu, int status) {
            handler.post(() -> onMtuSettled(g, status == BluetoothGatt.GATT_SUCCESS ? newMtu : DEFAULT_MTU));
        }

        private void onMtuSettled(BluetoothGatt g, int newMtu) {
            if (mtuSettled || finished) {
                return;
            }
            mtuSettled = true;
            mtu = newMtu;
            if (!g.discoverServices()) {
                fail("service discovery did not start");
            }
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt g, int status) {
            handler.post(() -> {
                if (finished) {
                    return;
                }
                BluetoothGattService service = g.getService(SERVICE_UUID);
                BluetoothGattCharacteristic ch = service == null ? null : service.getCharacteristic(CHARACTERISTIC_UUID);
                if (ch == null) {
                    fail("this device has no HexR service");
                    return;
                }
                characteristic = ch;
                if (closing) {
                    // Closed before it was ready. Subscribe anyway before letting go: a glove
                    // disconnected without ever having been subscribed can fault.
                    writeCccd();
                    return;
                }
                g.setCharacteristicNotification(ch, true);
                if (!writeCccd()) {
                    markReady();
                }
            });
        }

        /** The one subscription per connection. */
        @SuppressWarnings("deprecation")
        private boolean writeCccd() {
            if (cccdWritten || characteristic == null || gatt == null) {
                return false;
            }
            BluetoothGattDescriptor cccd = characteristic.getDescriptor(CCCD_UUID);
            if (cccd == null) {
                return false;
            }
            cccdWritten = true;
            boolean ok;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ok = gatt.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                        == BluetoothGatt.GATT_SUCCESS;
            } else {
                cccd.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
                ok = gatt.writeDescriptor(cccd);
            }
            if (ok) {
                handler.postDelayed(cccdTimeout, CCCD_TIMEOUT_MS);
            }
            return ok;
        }

        @Override
        public void onDescriptorWrite(BluetoothGatt g, BluetoothGattDescriptor d, int status) {
            handler.post(() -> {
                handler.removeCallbacks(cccdTimeout);
                if (closing && !ready) {
                    teardown();
                    return;
                }
                markReady();
            });
        }

        private void markReady() {
            if (ready || finished) {
                return;
            }
            ready = true;
            handler.removeCallbacks(connectTimeout);
            connectSettled(this);
            Log.d(TAG, "ready " + address + " MTU " + mtu);
            listener.onConnected(address, mtu);
            pump();
        }

        void enqueue(byte[] data, boolean purge) {
            if (finished) {
                return;
            }
            if (purge) {
                queue.clear();
            }
            for (byte[] chunk : FrameChunker.chunk(data, mtu - ATT_OVERHEAD)) {
                queue.addLast(chunk);
            }
            pump();
        }

        @SuppressWarnings("deprecation")
        private void pump() {
            if (busy || !ready || gatt == null || characteristic == null) {
                return;
            }
            if (queue.isEmpty()) {
                if (closing) {
                    teardown();
                }
                return;
            }
            long since = SystemClock.elapsedRealtime() - lastSendAt;
            int gap = minWriteGapMs;
            if (gap > 0 && since < gap) {
                handler.postDelayed(this::pump, gap - since);
                return;
            }
            byte[] data = queue.pollFirst();
            busy = true;
            boolean ok;
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    ok = gatt.writeCharacteristic(characteristic, data,
                            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothGatt.GATT_SUCCESS;
                } else {
                    characteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
                    characteristic.setValue(data);
                    ok = gatt.writeCharacteristic(characteristic);
                }
            } catch (RuntimeException e) {
                ok = false;
            }
            if (!ok) {
                busy = false;
                if (++writeFailures <= MAX_WRITE_RETRIES) {
                    queue.addFirst(data);
                } else {
                    Log.w(TAG, "dropping a write the stack keeps refusing");
                    writeFailures = 0;
                }
                handler.postDelayed(this::pump, 20);
                return;
            }
            writeFailures = 0;
            lastSendAt = SystemClock.elapsedRealtime();
            handler.postDelayed(writeTimeout, WRITE_TIMEOUT_MS);
        }

        @Override
        public void onCharacteristicWrite(BluetoothGatt g, BluetoothGattCharacteristic ch, int status) {
            handler.post(() -> {
                handler.removeCallbacks(writeTimeout);
                busy = false;
                pump();
            });
        }

        @Override
        public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic ch, byte[] value) {
            listener.onNotified(address, value.clone());
        }

        @Override
        @SuppressWarnings("deprecation")
        public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic ch) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                return; // the overload above handles it
            }
            byte[] value = ch.getValue();
            if (value != null) {
                listener.onNotified(address, value.clone());
            }
        }

        /** Sends what is queued (the release, normally), then closes. Reports nothing. */
        void close() {
            if (finished || closing) {
                return;
            }
            closing = true;
            connectQueue.remove(this);
            if (ready) {
                handler.postDelayed(forceClose, CLOSE_TIMEOUT_MS);
                pump();
            } else if (linkUp && !cccdWritten && characteristic != null) {
                if (writeCccd()) {
                    handler.postDelayed(forceClose, CCCD_TIMEOUT_MS);
                } else {
                    teardown();
                }
            } else if (linkUp && !mtuSettled || linkUp && characteristic == null) {
                // Services are still being discovered; subscribe when they arrive, then close.
                handler.postDelayed(forceClose, CCCD_TIMEOUT_MS + MTU_TIMEOUT_MS);
            } else {
                teardown();
            }
        }

        private void teardown() {
            if (finished) {
                return;
            }
            finished = true;
            ready = false;
            handler.removeCallbacks(forceClose);
            handler.removeCallbacks(writeTimeout);
            handler.removeCallbacks(connectTimeout);
            handler.removeCallbacks(cccdTimeout);
            queue.clear();
            if (gatt != null) {
                try {
                    gatt.disconnect();
                } catch (RuntimeException ignored) {
                    // closing anyway
                }
                try {
                    gatt.close();
                } catch (RuntimeException ignored) {
                    // closing anyway
                }
            }
            gatt = null;
            characteristic = null;
            sessions.remove(address, this);
            connectSettled(this);
            Log.d(TAG, "closed " + address);
        }
    }
}

package com.microtube.hexr.godot.ble;

import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Cuts a batch of glove frames into writes that fit one packet.
 *
 * The glove walks a write frame by frame using each frame's length byte, but it ignores a write
 * longer than one packet (MTU - 3): its firmware never decodes long (prepared) writes. So a batch
 * is cut on frame boundaries, never through a frame. Same rules as HexRFrames.chunk_for_mtu in
 * GDScript and the Windows extension; all three are checked against tests/fixtures/frames_split.json.
 */
final class FrameChunker {
    private FrameChunker() {
    }

    /** Splits by length byte, stopping at the first impossible length as the firmware does. */
    static List<byte[]> splitFrames(byte[] data) {
        List<byte[]> out = new ArrayList<>();
        int i = 0;
        while (i < data.length) {
            int length = data[i] & 0xFF;
            if (length <= 0 || length > data.length - i) {
                break;
            }
            out.add(Arrays.copyOfRange(data, i, i + length));
            i += length;
        }
        return out;
    }

    /** Packs whole frames into writes of at most maxPayload bytes. */
    static List<byte[]> chunk(byte[] data, int maxPayload) {
        List<byte[]> out = new ArrayList<>();
        if (data.length == 0) {
            return out;
        }
        if (maxPayload <= 0 || data.length <= maxPayload) {
            out.add(data);
            return out;
        }
        ByteArrayOutputStream current = new ByteArrayOutputStream();
        for (byte[] frame : splitFrames(data)) {
            if (current.size() > 0 && current.size() + frame.length > maxPayload) {
                out.add(current.toByteArray());
                current.reset();
            }
            current.write(frame, 0, frame.length);
        }
        if (current.size() > 0) {
            out.add(current.toByteArray());
        }
        return out;
    }
}

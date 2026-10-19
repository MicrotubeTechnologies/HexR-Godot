package com.microtube.hexr.godot.ble;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.junit.Test;

/** Checks the Java chunker against the fixture the GDScript and C++ chunkers also use. */
public class FrameChunkerTest {
    // The fixture is written by tools/gen_golden_frames.py with a fixed key order. org.json is
    // only a stub in local unit tests, so the few fields needed are read with patterns.
    private static final Pattern CASE = Pattern.compile(
            "\"name\": \"([^\"]+)\",\\s*\"hex\": \"([0-9a-f]*)\",\\s*\"max_payload\": (\\d+),\\s*\"chunks\": \\[([^\\]]*)\\]");
    private static final Pattern HEX = Pattern.compile("\"([0-9a-f]+)\"");

    private static byte[] hex(String s) {
        byte[] out = new byte[s.length() / 2];
        for (int i = 0; i < out.length; i++) {
            out[i] = (byte) Integer.parseInt(s.substring(i * 2, i * 2 + 2), 16);
        }
        return out;
    }

    private static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder();
        for (byte x : b) {
            sb.append(String.format("%02x", x & 0xFF));
        }
        return sb.toString();
    }

    @Test
    public void matchesSharedFixture() throws Exception {
        File f = new File("../../tests/fixtures/frames_split.json");
        String json = new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
        Matcher m = CASE.matcher(json);
        int cases = 0;
        while (m.find()) {
            cases++;
            List<String> want = new ArrayList<>();
            Matcher h = HEX.matcher(m.group(4));
            while (h.find()) {
                want.add(h.group(1));
            }
            List<String> got = new ArrayList<>();
            for (byte[] chunk : FrameChunker.chunk(hex(m.group(2)), Integer.parseInt(m.group(3)))) {
                got.add(hex(chunk));
            }
            assertEquals(m.group(1), want, got);
        }
        assertTrue("fixture has cases", cases >= 10);
    }

    @Test
    public void releaseFitsMinimumMtuOneFramePerWrite() {
        byte[] frame = hex("120409000000000101010209000070410164");
        byte[] all = new byte[frame.length * 12];
        for (int i = 0; i < 12; i++) {
            System.arraycopy(frame, 0, all, i * frame.length, frame.length);
        }
        List<byte[]> chunks = FrameChunker.chunk(all, 20);
        assertEquals(12, chunks.size());
        for (byte[] c : chunks) {
            assertEquals(18, c.length);
        }
    }
}

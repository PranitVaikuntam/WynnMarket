package net.pranit.wynnmarket.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ScanHeartbeatTest {
    @TempDir Path tempDir;

    @Test void writesEpochMarkerAtomically() throws Exception {
        Path marker = tempDir.resolve("health/scan");
        ScanHeartbeat heartbeat = new ScanHeartbeat(
            marker, Clock.fixed(Instant.ofEpochSecond(1_700_000_000L), ZoneOffset.UTC));
        assertTrue(heartbeat.emit());
        assertEquals("1700000000", Files.readString(marker));
    }
}

package net.pranit.wynnmarket.service;

import net.pranit.wynnmarket.WynnMarket;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Clock;
import java.time.Instant;

public final class ScanHeartbeat {
    private static final String DEFAULT_PATH = "/tmp/wynnmarket/last-valid-scan";
    private final Path marker;
    private final Clock clock;

    public ScanHeartbeat() {
        this(Path.of(System.getenv().getOrDefault("WYNNMARKET_HEALTH_MARKER", DEFAULT_PATH)), Clock.systemUTC());
    }

    ScanHeartbeat(Path marker, Clock clock) {
        this.marker = marker;
        this.clock = clock;
    }

    public boolean emit() {
        Instant now = clock.instant();
        Path temporary = marker.resolveSibling(marker.getFileName() + ".tmp");
        try {
            if (marker.getParent() != null) Files.createDirectories(marker.getParent());
            Files.writeString(temporary, Long.toString(now.getEpochSecond()), StandardCharsets.UTF_8);
            try {
                Files.move(temporary, marker, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            } catch (IOException ignored) {
                Files.move(temporary, marker, StandardCopyOption.REPLACE_EXISTING);
            }
            WynnMarket.LOGGER.info("event=scan_heartbeat timestamp={} marker={}", now, marker);
            return true;
        } catch (IOException error) {
            WynnMarket.LOGGER.error("event=health_marker_failure marker={}", marker, error);
            return false;
        }
    }
}

# WynnMarket

WynnMarket is an unattended Minecraft 1.21.11/Fabric client that enters Wynncraft's Trade Market and scans new listings. This branch is a local-testing build: it has no cloud dependencies, infrastructure, or deployment scripts. The client runs in HeadlessMC 2.10.0 with Wynntils 4.2.19 and Wynnventory 2.2.5.

## Runtime behavior

The container supervisor launches `fabric:1.21.11 -lwjgl`, waits for the mod, and sends `connect play.wynncraft.com`. The mod accepts the server resource pack, waits for a valid player and target, performs the loading-exit click and Auction House click with bounded retries, verifies the Trade Market screen, and starts scanning. It logs structured `event=...` markers for each transition.

A valid scan atomically updates `/tmp/wynnmarket/last-valid-scan`. The container exits if the first scan misses the startup deadline or a marker becomes more than ten minutes old. Docker's `unless-stopped` policy then restarts the entire launch/connect sequence. The Docker health check is healthy only while that marker is fresh.

Runtime settings and defaults:

```text
WYNNMARKET_SERVER_ADDRESS=play.wynncraft.com
WYNNMARKET_STARTUP_TIMEOUT_SECONDS=600
WYNNMARKET_SCAN_TIMEOUT_SECONDS=600
WYNNMARKET_HEALTH_MARKER=/tmp/wynnmarket/last-valid-scan
```

## Build and test

Requirements are Java 21 and Docker. Build artifacts and credentials are never copied from `.env` into the image.

```bash
cd fabric
./gradlew clean test build
cd ..
docker/test-entrypoint.sh
```

The shell smoke test stubs HeadlessMC, verifies automatic launch/connect/health, and verifies that a missing initial scan terminates the supervisor. Build the image with:

```bash
docker build --platform linux/amd64 -f docker/Dockerfile -t wynnmarket-headless:latest .
```

The image requires a nonempty persisted account file mounted at:

```text
/headlessmc/HeadlessMC/auth/.accounts.json
```

## Local testing

Build the mod and image, then run it locally with a mounted account file:

```bash
./scripts/build-local-image.sh
./scripts/run-local-container.sh
```

`run-local-container.sh` copies `auth/.accounts.json` into `auth-local/` and bind-mounts it into the container so the source account file stays untouched. Override `SERVER_ADDRESS`, `LOCAL_AUTH_FILE`, or `LOCAL_CONTAINER_NAME` via environment variables as needed.

### Reauthentication

Microsoft refresh tokens normally renew unattended. If the token is revoked or permanently expires, mount the auth file into a temporary HeadlessMC container, perform the one-time `login` device flow, and write only the resulting `.accounts.json` back. Never commit the account file to Git.

### Recovery tests

- Stop the container and verify `unless-stopped` starts it again.
- Temporarily prevent new scan markers and verify exit/restart after `WYNNMARKET_SCAN_TIMEOUT_SECONDS`.

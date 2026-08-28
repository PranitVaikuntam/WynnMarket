package net.pranit.wynnmarket.service;

import com.wynnventory.model.container.TrademarketContainer;
import com.wynnventory.model.item.trademarket.TrademarketListing;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ConfirmScreen;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.screen.ingame.HandledScreen;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.util.Hand;
import net.pranit.wynnmarket.WynnMarket;

import java.util.Random;

public enum AuctionScannerManager {
    INSTANCE;

    private static final int TICKS_UNTIL_SCAN = 20;
    private static final int CLICK_DELAY_TICKS = 100;
    private static final int PLAYER_WAIT_TICKS = 60 * 20;
    private static final int RECONNECT_COOLDOWN_TICKS = 15 * 20;
    private static final int MAX_LOADING_CLICK_ATTEMPTS = 3;
    private static final int MAX_MARKET_CLICK_ATTEMPTS = 5;

    private final AuctionStartupStateMachine startup = new AuctionStartupStateMachine(
        CLICK_DELAY_TICKS, PLAYER_WAIT_TICKS, RECONNECT_COOLDOWN_TICKS,
        MAX_LOADING_CLICK_ATTEMPTS, MAX_MARKET_CLICK_ATTEMPTS
    );
    private final ScanHeartbeat heartbeat = new ScanHeartbeat();
    private final Random random = new Random();
    private AuctionStartupStateMachine.State loggedState;
    private int tickScanCounter = -1;
    private boolean scanLock;
    private int tickResetCounter = nextResetTicks();
    private AuctionScanner auctionScanner = new AuctionScanner();

    public void tick() {
        MinecraftClient client = MinecraftClient.getInstance();
        if (acceptResourcePackPrompt(client.currentScreen)) return;

        //Determine next action
        boolean marketOpen = isTradeMarketScreen(client.currentScreen);
        boolean playerReady = client.player != null && client.interactionManager != null;
        boolean validTarget = playerReady && client.targetedEntity != null;
        AuctionStartupStateMachine.Action action = startup.tick(
            new AuctionStartupStateMachine.Observation(playerReady, validTarget, marketOpen));
        logStateTransition();

        //Take next action
        if (action == AuctionStartupStateMachine.Action.CLICK_TARGET) {
            clickTarget(client);
        } else if (action == AuctionStartupStateMachine.Action.REQUEST_RECONNECT) {
            WynnMarket.LOGGER.warn("event=reconnect_requested reason=startup_retry_exhausted");
            resetScanner();
        }

        if (!marketOpen) return;
        tickResetCounter--;
        runScheduledScan();
        if (tickResetCounter <= 0 && !scanLock) {
            WynnMarket.LOGGER.info("event=afk_reset action=close_market_screen");
            if (client.currentScreen != null) client.currentScreen.close();
            resetScanner();
            tickResetCounter = nextResetTicks();
        }
    }

    private boolean acceptResourcePackPrompt(Screen screen) {
        if (!(screen instanceof ConfirmScreen)) return false;
        if (!ResourcePackPromptPolicy.isResourcePackPrompt(screen.getTitle().getString())) return false;
        for (var element : screen.children()) {
            if (element instanceof ButtonWidget button && button.active) {
                if (ResourcePackPromptPolicy.isAcceptButton(button.getMessage().getString())) {
                    WynnMarket.LOGGER.info("event=resource_pack_accept button={}", button.getMessage().getString());
                    button.onPress(null);
                    return true;
                }
            }
        }
        WynnMarket.LOGGER.info("event=resource_pack_wait reason=accept_button_not_ready");
        return true;
    }

    private void clickTarget(MinecraftClient client) {
        if (client.player == null || client.interactionManager == null || client.targetedEntity == null) {
            WynnMarket.LOGGER.warn("event=click_skipped reason=missing_player_or_target state={}", startup.state());
            return;
        }
        client.interactionManager.attackEntity(client.player, client.targetedEntity);
        client.player.swingHand(Hand.MAIN_HAND);
        WynnMarket.LOGGER.info("event=target_clicked state={} target_type={}",
            startup.state(), client.targetedEntity.getType().toString());
    }

    private void runScheduledScan() {
        if (tickScanCounter < 0) return;
        if (--tickScanCounter > 0) return;
        scanLock = true;
        tickScanCounter = -1;
        try {
            WynnMarket.LOGGER.info("event=scan_started");
            AuctionScanner.ScanResult result = auctionScanner.scan();
            if (!result.valid()) {
                WynnMarket.LOGGER.warn("event=scan_invalid reason=trade_market_screen_changed");
                return;
            }
            TrademarketListing[] newListings = result.newListings();
            auctionScanner.printTradeMarketListings("currPage", newListings);
            heartbeat.emit();
            DynamoDbListingWriter.sendListingsToDynamoDb(newListings);
        } finally {
            scanLock = false;
        }
    }

    public void scheduleScan() {
        if (!scanLock && startup.state() == AuctionStartupStateMachine.State.SCANNING) {
            tickScanCounter = TICKS_UNTIL_SCAN;
        }
    }

    private boolean isTradeMarketScreen(Screen screen) {
        return screen instanceof HandledScreen<?> handledScreen
            && TrademarketContainer.matchesTitle(handledScreen.getTitle().getString());
    }

    private void resetScanner() {
        auctionScanner = new AuctionScanner();
        tickScanCounter = -1;
    }

    private void logStateTransition() {
        if (loggedState != startup.state()) {
            WynnMarket.LOGGER.info("event=startup_state state={}", startup.state());
            loggedState = startup.state();
            if (loggedState == AuctionStartupStateMachine.State.SCANNING && tickScanCounter < 0) {
                tickScanCounter = TICKS_UNTIL_SCAN;
            }
        }
    }

    private int nextResetTicks() {
        return random.nextInt(2 * 60 * 20) + (2 * 60 * 20);
    }
}

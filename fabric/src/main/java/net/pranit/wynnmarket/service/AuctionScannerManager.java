package net.pranit.wynnmarket.service;

import com.wynnventory.model.container.TrademarketContainer;
import com.wynnventory.model.item.trademarket.TrademarketListing;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.screen.ingame.HandledScreen;
import net.minecraft.util.Hand;
import net.pranit.wynnmarket.WynnMarket;

import java.util.Random;

/**
 * An auction scanner object can function for around 10 minutes. After that the player wiu
 */
public enum AuctionScannerManager {
    INSTANCE;

    private final int TICKS_UNTIL_SCAN = 20;
    private int tickScanCounter = -1;
    private boolean scanLock = false;

    private final int TICKS_UNTIL_CLICK = 100;
    private int tickClickCounter =  TICKS_UNTIL_CLICK;

    private int tickResetCounter = (new Random().nextInt(2 * 60 * 20)) + (2 * 60 * 20);

    private AuctionScanner auctionScanner = new AuctionScanner();


    private AuctionScannerManager() {}

    /**
	 * This function is registered to be called on every tick in WynnMarket.java.
     * By definition, a move can only happen after a scan has just run. There is no possible way for a scan to interrupt a run
	 * However, we must stop the scan code from early returning from tick once a run has been scheduled
	 */
	public void tick() {
        //Wait some time after the click before doing anything
        if (tickClickCounter > 0) {
            tickClickCounter--;
            return;
        }

        //Click until get to auction screen
        Screen currentScreen = MinecraftClient.getInstance().currentScreen;
        if (!((currentScreen instanceof HandledScreen<?> handledScreen) &&
            (TrademarketContainer.matchesTitle(handledScreen.getTitle().getString()))
        )) {
            WynnMarket.LOGGER.info("Clicking to get to Auction Screen");
            click();
            auctionScanner = new AuctionScanner();
            tickClickCounter = TICKS_UNTIL_CLICK;
            return;
        }


        tickResetCounter--;

        //A scan has not been scheduled
        if (tickScanCounter < 0) return;
        //A scan has been scheduled. Lock any scans from being scheduled
        tickScanCounter--;
        if (tickScanCounter > 0) return;
        scanLock = true;
        //A scan runs
        try {
            tickScanCounter = -1;
            scan();
        } finally {
            scanLock = false;
        }

        //We have not moved in between 2 - 4 minutes and now need to move
        if (tickResetCounter < 0) {
            WynnMarket.LOGGER.info("Moving to avoid AFK");
            scanLock = true;

            //Stop AFK.
            pressEscape();

            //reset auction scanner and timers
            auctionScanner = new AuctionScanner();
            tickResetCounter = (new Random().nextInt(2 * 60 * 20)) + (2 * 60 * 20);
            scanLock = false;
        }
    }

    /**
     * Press Escape
     */
    public static void pressEscape() {
        MinecraftClient client = MinecraftClient.getInstance();

        if (client.currentScreen != null) {
            client.currentScreen.close();
        }
    }

    /**
     * Click
     */
    private void click() {
        MinecraftClient client = MinecraftClient.getInstance();

        if (client.player != null && client.interactionManager != null && client.targetedEntity != null) {
            client.interactionManager.attackEntity(client.player, client.targetedEntity);
            client.player.swingHand(Hand.MAIN_HAND);
        }
    }

	/**
	 * Schedule a scanning to happen in TICKS_UNTIL_SCAN ticks by setting TICKS_UNTIL_SCAN. Do not anything if a scan is already happening
	 */
	public void scheduleScan() {
        //Only schedule a run if a scan is not running
        if (!scanLock) {
            tickScanCounter = TICKS_UNTIL_SCAN;
        }
	}

    /**
     * Scans page and sends it to AWS
     */
    private void scan() {
        WynnMarket.LOGGER.info("Scanning Current Auction Page");
        TrademarketListing[] newListings = auctionScanner.getNewListings();
        auctionScanner.printTradeMarketListings("currPage", newListings);
        DynamoDbListingWriter.sendListingsToDynamoDb(newListings);
    }
}

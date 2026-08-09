package net.pranit.wynnmarket.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jdk8.Jdk8Module;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.wynnventory.model.item.trademarket.TrademarketListing;
import net.minecraft.client.MinecraftClient;
import net.minecraft.util.Hand;
import net.pranit.wynnmarket.WynnMarket;

import java.util.List;
import java.util.Random;

/**
 * An auction scanner object can function for around 10 minutes. After that the player wiu
 */
public enum AuctionScannerManager {
    INSTANCE;

    private final int TICKS_UNTIL_SCAN = 20;
    private final int TICKS_UNTIL_CLICK = 2;

    private int tickScanCounter = -1;
    private int tickMoveCounter = (new Random().nextInt(3 * 60 * 20)) + (3 * 60 * 20);;
    private int tickClickCounter =  TICKS_UNTIL_CLICK;

    private AuctionScanner auctionScanner = new AuctionScanner();
    private boolean moveRunning = false;

    private AuctionScannerManager() {}

    /**
	 * This function is registered to be called on every tick in WynnMarket.java.
     * By definition, a move can only happen after a scan has just run. There is no possible way for a scan to interrupt a run
	 * However, we must stop the scan code from early returning from tick once a run has been scheduled
	 */
	public void tick() {
        tickMoveCounter--; //Count down for move time

        if (!moveRunning) {
            //A scan has not been scheduled
            if (tickScanCounter < 0) return;
            //A scan has been scheduled
            tickScanCounter--;
            if (tickScanCounter > 0) return;
            //A scan runs
            tickScanCounter = -1;
            scan();
        }

        //We have not moved in between 5 - 10 minutes and now need to move
        if (tickMoveCounter < 0) {
            WynnMarket.LOGGER.info("Moving to avoid AFK");
            moveRunning = true;

            //Stop AFK. Wait a couple ticks before clicking back in
            pressEscape();
            tickClickCounter--;
            if (tickClickCounter > 0) return;
            click();

            //reset auction scanner and timers
            auctionScanner = new AuctionScanner();
            tickMoveCounter = (new Random().nextInt(5 * 60 * 20)) + (5 * 60 * 20);
            tickClickCounter = TICKS_UNTIL_CLICK;
            moveRunning = false;
        }
	}

	/**
	 * Schedule a scanning to happen in TICKS_UNTIL_SCAN ticks by setting TICKS_UNTIL_SCAN. Do not anything if a scan is already happening
	 */
	public void scheduleScan() {
		tickScanCounter = TICKS_UNTIL_SCAN;
	}

    /**
     * Scans page and sends it to AWS
     */
    private void scan() {
        WynnMarket.LOGGER.info("Scanning Current Auction Page");
        TrademarketListing[] newListings = auctionScanner.getNewListings();
        auctionScanner.printTradeMarketListings("currPage", newListings);
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
}

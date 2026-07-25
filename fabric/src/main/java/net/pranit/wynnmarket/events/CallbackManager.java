package net.pranit.wynnmarket.events;

import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.pranit.wynnmarket.WynnMarket;
import net.pranit.wynnmarket.service.AuctionScanner;

public enum CallbackManager {
	INSTANCE;

	private boolean initialized;

	public void initialize() {
		if (initialized) {
			return;
		}

		initialized = true;
		registerCallbacks();
	}

	private void registerCallbacks() {
		TradeMarketOpenedCallback.EVENT.register(() -> {
			WynnMarket.LOGGER.info("Trade Market screen initialized.");
//			AuctionScanner.INSTANCE.scheduleScan();
		});
	}
}

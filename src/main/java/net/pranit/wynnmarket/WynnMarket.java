package net.pranit.wynnmarket;

import net.fabricmc.api.ModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.pranit.wynnmarket.events.CallbackManager;
import net.pranit.wynnmarket.service.AuctionScannerManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class WynnMarket implements ModInitializer {
	public static final String MOD_ID = "wynnmarket";

	// This logger is used to write text to the console and the log file.
	// It is considered best practice to use your mod id as the logger's name.
	// That way, it's clear which mod wrote info, warnings, and errors.
	public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);

	@Override
	public void onInitialize() {
		// This code runs as soon as Minecraft is in a mod-load-ready state.
		// However, some things (like resources) may still be uninitialized.
		// Proceed with mild caution.

		CallbackManager.INSTANCE.initialize();

		LOGGER.info("WynnMarket initialized.");

		ClientTickEvents.END_CLIENT_TICK.register(client -> {
			AuctionScannerManager.INSTANCE.tick();
		});

	}
}

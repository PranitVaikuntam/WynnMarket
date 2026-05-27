package net.pranit.wynnmarket.service;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.screen.ingame.HandledScreen;
import net.minecraft.screen.slot.Slot;
import net.pranit.wynnmarket.WynnMarket;
import net.pranit.wynnmarket.model.container.TradeMarketContainer;

public enum AuctionScanner {
	INSTANCE;

	private static final int SETTLE_TICKS = 2;

	private int ticksUntilScan = -1;

	public void scheduleScan() {
		ticksUntilScan = SETTLE_TICKS;
	}

	public void tick(MinecraftClient client) {
		if (ticksUntilScan < 0) {
			return;
		}

		if (ticksUntilScan-- > 0) {
			return;
		}

		ticksUntilScan = -1;
		scanCurrentPage(client);
	}

	private void scanCurrentPage(MinecraftClient client) {
		Screen currentScreen = client.currentScreen;
		if (!(currentScreen instanceof HandledScreen<?> handledScreen)) {
			return;
		}

		if (!TradeMarketContainer.matchesTitle(handledScreen.getTitle().getString())) {
			return;
		}

		WynnMarket.LOGGER.info("Scanning settled Trade Market page.");

		for (Slot slot : handledScreen.getScreenHandler().slots) {
			if (slot.hasStack()) {
				// Record the settled item state from slot.getStack() here.
				WynnMarket.LOGGER.debug("Found item stack in slot {}: {}", slot.id, slot.getStack());
			}
		}
	}
}

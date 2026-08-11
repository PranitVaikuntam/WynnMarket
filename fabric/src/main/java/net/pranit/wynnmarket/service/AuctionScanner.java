package net.pranit.wynnmarket.service;


import com.wynnventory.model.item.trademarket.TrademarketListing;
import com.wynnventory.model.item.simple.SimpleItem;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.screen.ingame.HandledScreen;
import net.minecraft.item.ItemStack;
import net.pranit.wynnmarket.WynnMarket;
import net.pranit.wynnmarket.exception.IncorrectScreenException;

public class AuctionScanner {

	public boolean initialized = false;
	private final int NUM_ITEMS = 45;
	TrademarketListing[] prevPage;
	TrademarketListing[] currPage;

	/**
	 * Get new listings from the auction page
	 * @return a list of the new listings or an empty list if there is nothing to return
	 */
	public TrademarketListing[] getNewListings() {
		//On initialization, you must first start with a prevPage
		if(!initialized) {
			//Check if initialization failed
			try {
				prevPage = getPage();
			} catch (IncorrectScreenException e) {
				return new TrademarketListing[0];
            }
            initialized = true;
			return new TrademarketListing[0];
		}

		//Update the current page
		try {
			currPage = getPage();
		} catch (IncorrectScreenException e) {
			return new TrademarketListing[0];
		}

		//Find the new listings
		PageChangeDetector<ItemStack, TrademarketListing> auctionScanner = new PageChangeDetector<>(
			NUM_ITEMS,
			prevPage,
			currPage,
			TrademarketListing[]::new
		);
		TrademarketListing[] resultAuctionPageDiff = auctionScanner.findPageDiff();

		//Update the prevPage to be the currPage
		prevPage = currPage;

		return resultAuctionPageDiff;
	}

	/**
	 * Scan all the items on the current screen.
	 * @throws IncorrectScreenException if the current screen is not an handled screen
	 * @return a list of the items on the current screen
	 */
	private TrademarketListing[] getPage() throws IncorrectScreenException {
		//Get screen
		Screen currentScreen = MinecraftClient.getInstance().currentScreen;
		if (!(currentScreen instanceof HandledScreen<?> handledScreen)) {
			WynnMarket.LOGGER.warn("Tried to scan auction slots while no handled screen was open.");
			throw new IncorrectScreenException("Tried to scan auction slots while no handled screen was open.");
		}

		//Get items
		TrademarketListing[] listings = new TrademarketListing[NUM_ITEMS];
		for (int slotIndex = 0; slotIndex < NUM_ITEMS; slotIndex++) {
			//Get a listing from an item
			ItemStack stack = handledScreen.getScreenHandler().getSlot(slotIndex).getStack();
			if(stack == null) {
				WynnMarket.LOGGER.error("NULL ITEM");
			}
			listings[slotIndex] = TrademarketListing.from(stack);
		}

		return listings;
	}

	public void printTradeMarketListings(String label, TrademarketListing[] listings) {
		if (listings == null) {
			WynnMarket.LOGGER.info("{}: null", label);
			return;
		}

		StringBuilder message = new StringBuilder();
		message.append(label).append(" length=").append(listings.length);

		for (int slotIndex = 0; slotIndex < listings.length; slotIndex++) {
			TrademarketListing listing = listings[slotIndex];

			message
				.append("\n[")
				.append(slotIndex)
				.append("] ");

			if (listing == null) {
				message.append("null");
				continue;
			}

			SimpleItem item = listing.getItem();
			String itemName = item == null ? "unknown item" : item.getName();
			message
				.append(itemName)
				.append(" x")
				.append(listing.getQuantity());
		}

		WynnMarket.LOGGER.info(message.toString());
	}
}

package net.pranit.wynnmarket.events;

import net.fabricmc.fabric.api.event.Event;
import net.fabricmc.fabric.api.event.EventFactory;

public interface TradeMarketOpenedCallback {
	Event<TradeMarketOpenedCallback> EVENT = EventFactory.createArrayBacked(
			TradeMarketOpenedCallback.class,
			listeners -> () -> {
				for (TradeMarketOpenedCallback listener : listeners) {
					listener.onTradeMarketOpened();
				}
			}
	);

	void onTradeMarketOpened();
}

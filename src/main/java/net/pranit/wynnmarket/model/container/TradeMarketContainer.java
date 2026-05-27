package net.pranit.wynnmarket.model.container;

import java.util.regex.Pattern;

public final class TradeMarketContainer {
	private static final Pattern TITLE = Pattern.compile("\uDAFF\uDFE8\uE011");

	private TradeMarketContainer() {
	}

	public static boolean matchesTitle(String title) {
		return title != null && TITLE.matcher(title).find();
	}
}

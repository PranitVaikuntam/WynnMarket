package net.pranit.wynnmarket.mixin;

import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.screen.ingame.HandledScreen;
import net.minecraft.text.Text;
import net.pranit.wynnmarket.events.TradeMarketOpenedCallback;
import net.pranit.wynnmarket.model.container.TradeMarketContainer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(HandledScreen.class)
public abstract class HandledScreenMixin extends Screen {
	protected HandledScreenMixin(Text title) {
		super(title);
	}

	@Inject(method = "init", at = @At("RETURN"))
	private void onInitialized(CallbackInfo ci) {
		if (TradeMarketContainer.matchesTitle(this.getTitle().getString())) {
			TradeMarketOpenedCallback.EVENT.invoker().onTradeMarketOpened();
		}
	}
}

package net.pranit.wynnmarket.mixin;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.screen.ingame.HandledScreen;
import net.minecraft.item.ItemStack;
import net.minecraft.screen.ScreenHandler;
import net.pranit.wynnmarket.model.container.TradeMarketContainer;
import net.pranit.wynnmarket.service.AuctionScanner;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ScreenHandler.class)
public abstract class ScreenHandlerMixin {
    @Inject(method = "setStackInSlot", at = @At("RETURN"))
    private void afterSlotUpdated(int slotIndex, int revision, ItemStack stack, CallbackInfo ci) {
        scheduleScanIfTradeMarket();
    }

    private static void scheduleScanIfTradeMarket() {
        Screen currentScreen = MinecraftClient.getInstance().currentScreen;

        if (!(currentScreen instanceof HandledScreen<?> handledScreen)) {
            return;
        }

        if (!TradeMarketContainer.matchesTitle(handledScreen.getTitle().getString())) {
            return;
        }

        AuctionScanner.INSTANCE.scheduleScan();
    }
}

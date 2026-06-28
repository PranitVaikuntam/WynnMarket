package net.pranit.wynnmarket.mixin;


import com.wynnventory.model.container.TrademarketContainer;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.screen.ingame.HandledScreen;
import net.minecraft.item.ItemStack;
import net.minecraft.screen.ScreenHandler;
import net.pranit.wynnmarket.service.AuctionScannerManager;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Mixin for the ScreenHandler class. This will be used for the Auction House Screen.
 */
@Mixin(ScreenHandler.class)
public abstract class ScreenHandlerMixin {

    /**
     * Through this code, we are essentially subscribing to the event of updating the Auction House Page
     * @param slotIndex The slot being updated
     * @param revision Ignore
     * @param stack The item information for the slot being updated.
     * @param ci Ignore
     */
    @Inject(method = "setStackInSlot", at = @At("RETURN"))
    private void afterSlotUpdated(int slotIndex, int revision, ItemStack stack, CallbackInfo ci) {
        //Check if the current screen opened is the trade market screen
        Screen currentScreen = MinecraftClient.getInstance().currentScreen;
        if (!(currentScreen instanceof HandledScreen<?> handledScreen)) return;
        if (!TrademarketContainer.matchesTitle(handledScreen.getTitle().getString())) return;

        //Run only once on trade market update
        if(slotIndex == 0) AuctionScannerManager.INSTANCE.scheduleScan();
    }

}

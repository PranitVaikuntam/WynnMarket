package net.pranit.wynnmarket.service;

import org.junit.jupiter.api.Test;
import static net.pranit.wynnmarket.service.AuctionStartupStateMachine.Action.*;
import static net.pranit.wynnmarket.service.AuctionStartupStateMachine.State.SCANNING;
import static net.pranit.wynnmarket.service.AuctionStartupStateMachine.State.WAITING_AFTER_LOADING_CLICK;
import static org.junit.jupiter.api.Assertions.assertEquals;

class AuctionStartupStateMachineTest {
    private static final AuctionStartupStateMachine.Observation READY_TARGET =
        new AuctionStartupStateMachine.Observation(true, true, false);

    @Test void performsBothClicksAndWaitsForMarket() {
        AuctionStartupStateMachine machine = machine();
        assertEquals(CLICK_TARGET, machine.tick(READY_TARGET));
        assertEquals(NONE, machine.tick(READY_TARGET));
        assertEquals(CLICK_TARGET, machine.tick(READY_TARGET));
        assertEquals(NONE, machine.tick(new AuctionStartupStateMachine.Observation(true, false, true)));
        assertEquals(SCANNING, machine.state());
        assertEquals(1, machine.loadingClickAttempts());
        assertEquals(1, machine.marketClickAttempts());
    }

    @Test void neverClicksWithoutPlayerAndTarget() {
        AuctionStartupStateMachine machine = machine();
        assertEquals(NONE, machine.tick(new AuctionStartupStateMachine.Observation(false, false, false)));
        assertEquals(NONE, machine.tick(new AuctionStartupStateMachine.Observation(true, false, false)));
        assertEquals(0, machine.loadingClickAttempts());
    }

    @Test void requestsReconnectAfterBoundedMarketRetries() {
        AuctionStartupStateMachine machine = machine();
        assertEquals(CLICK_TARGET, machine.tick(READY_TARGET));
        assertEquals(NONE, machine.tick(READY_TARGET));
        assertEquals(CLICK_TARGET, machine.tick(READY_TARGET));
        assertEquals(NONE, machine.tick(READY_TARGET));
        assertEquals(NONE, machine.tick(READY_TARGET)); // route back to loading-click wait
        assertEquals(NONE, machine.tick(READY_TARGET));
        assertEquals(CLICK_TARGET, machine.tick(READY_TARGET));
        assertEquals(NONE, machine.tick(READY_TARGET));
        assertEquals(NONE, machine.tick(READY_TARGET)); // route back to loading-click wait
        assertEquals(NONE, machine.tick(READY_TARGET));
        assertEquals(CLICK_TARGET, machine.tick(READY_TARGET));
        assertEquals(NONE, machine.tick(READY_TARGET));
        assertEquals(REQUEST_RECONNECT, machine.tick(READY_TARGET));
        assertEquals(3, machine.marketClickAttempts());
    }

    @Test void routesFailedMarketOpenBackThroughLoadingClickWait() {
        AuctionStartupStateMachine machine = machine();
        assertEquals(CLICK_TARGET, machine.tick(READY_TARGET));
        assertEquals(NONE, machine.tick(READY_TARGET));
        assertEquals(CLICK_TARGET, machine.tick(READY_TARGET));
        assertEquals(NONE, machine.tick(READY_TARGET));

        // The market did not open, so the next retry follows the same delayed
        // path as the original market click.
        assertEquals(NONE, machine.tick(READY_TARGET));
        assertEquals(WAITING_AFTER_LOADING_CLICK, machine.state());
    }

    @Test void requestsReconnectWhenPlayerNeverAppears() {
        AuctionStartupStateMachine machine = machine();
        var missing = new AuctionStartupStateMachine.Observation(false, false, false);
        assertEquals(NONE, machine.tick(missing));
        assertEquals(NONE, machine.tick(missing));
        assertEquals(NONE, machine.tick(missing));
        assertEquals(REQUEST_RECONNECT, machine.tick(missing));
    }

    private AuctionStartupStateMachine machine() {
        return new AuctionStartupStateMachine(2, 4, 2, 2, 3);
    }
}

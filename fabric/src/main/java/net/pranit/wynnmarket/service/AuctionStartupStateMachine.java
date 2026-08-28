package net.pranit.wynnmarket.service;

import java.util.Objects;

/**
 * State machine that handles the logic for starting up the auction scanner. 
 * It tracks the current state, the number of ticks spent in that state, and the number of attempts made to click on the loading screen and market buttons. 
 * 
 * AuctionStartupStateMachine
 */
public final class AuctionStartupStateMachine {
    public enum State {
        WAITING_FOR_PLAYER, //Waiting for player to load into game
        WAITING_AFTER_LOADING_CLICK, //Waiting after clicking into the game
        WAITING_FOR_MARKET, //Waiting after clicking into the market
        SCANNING, //Scanning the market
        RECONNECT_COOLDOWN, //Reconneting to the server after some failure
        FAILED //If after all attempts, the scanner failed to start up, move to a failed state
    }

    public enum Action { NONE, CLICK_TARGET, REQUEST_RECONNECT }

    public record Observation(boolean playerReady, boolean validTarget, boolean marketOpen) {}

    private final int clickDelayTicks; //Amount of ticks to wait after clicking before checking state
    private final int playerWaitTicks; //Amount of ticks to wait for the player to load into the game
    private final int reconnectCooldownTicks; 
    private final int maxLoadingClickAttempts; //Maximum number of attempts to click the loading screen before requesting a reconnect
    private final int maxMarketClickAttempts; //Maximum number of attempts to click the market button before requesting a reconnect
    private State state = State.WAITING_FOR_PLAYER;
    private int ticksInState;
    private int loadingClickAttempts;
    private int marketClickAttempts;

    public AuctionStartupStateMachine(int clickDelayTicks, int playerWaitTicks, int reconnectCooldownTicks,
                                      int maxLoadingClickAttempts, int maxMarketClickAttempts) {
        if (clickDelayTicks < 1 || playerWaitTicks < 1 || reconnectCooldownTicks < 1) {
            throw new IllegalArgumentException("Tick limits must be positive");
        }
        if (maxLoadingClickAttempts < 1 || maxMarketClickAttempts < 1) {
            throw new IllegalArgumentException("Retry limits must be positive");
        }
        this.clickDelayTicks = clickDelayTicks;
        this.playerWaitTicks = playerWaitTicks;
        this.reconnectCooldownTicks = reconnectCooldownTicks;
        this.maxLoadingClickAttempts = maxLoadingClickAttempts;
        this.maxMarketClickAttempts = maxMarketClickAttempts;
    }

    /**
     * Every tick, this function is run through the AuctionScannerManager tick subscription.
     * It observes the current state of the game and determines what action to take next based on the current state and the observations provided.
     * @param observation Observation about the current state of the ganme
     * @return Action to take next based on the current state and observations
     */
    public Action tick(Observation observation) {
        Objects.requireNonNull(observation, "observation");
        //If market is open, we should be in scanning state, and we can continue in this loop 
        if (observation.marketOpen()) {
            transition(State.SCANNING);
            return Action.NONE;
        }
        //If market is not open, but the state is scanning, then that means we have lost the market screen
        if (state == State.SCANNING) transition(State.WAITING_FOR_PLAYER);
        
        //Make an action depending on the current state
        ticksInState++;
        return switch (state) {
            case WAITING_FOR_PLAYER -> waitForPlayer(observation);
            case WAITING_AFTER_LOADING_CLICK -> waitAfterLoadingClick(observation);
            case WAITING_FOR_MARKET -> waitForMarket();
            case RECONNECT_COOLDOWN -> waitForReconnectCooldown();
            case SCANNING, FAILED -> Action.NONE;
        };
    }


    /**
     * Check if the player had loaded into the game. If so, click to get past the loading screen
     * @param observation Observation about the current state of the game
     * @return Action to take next
     */
    private Action waitForPlayer(Observation observation) {
        if (observation.playerReady() && observation.validTarget()) {
            loadingClickAttempts++;
            transition(State.WAITING_AFTER_LOADING_CLICK);
            return Action.CLICK_TARGET;
        }
        return ticksInState >= playerWaitTicks ? requestReconnect() : Action.NONE;
    }

    /**
     * Wait after clicking the loading screen to ensure the player has loaded. If they have, try to click into the market.
     * If not in the loading screen, then move back to waiting for player. If the player has not loaded after the maximum number of attempts, request a reconnect.
     * @param observation Observation about the current state of the game
     * @return Action to take next
     */
    private Action waitAfterLoadingClick(Observation observation) {
        if (ticksInState < clickDelayTicks) return Action.NONE;
        if (observation.playerReady() && observation.validTarget()) {
            marketClickAttempts++;
            transition(State.WAITING_FOR_MARKET);
            return Action.CLICK_TARGET;
        }
        if (loadingClickAttempts < maxLoadingClickAttempts) {
            transition(State.WAITING_FOR_PLAYER);
            return Action.NONE;
        }
        return requestReconnect();
    }

    /**
     * Wait for the market screen to appear. If it does not appear after the maximum number of attempts, request a reconnect.
]     * @return Action to take next
     */
    private Action waitForMarket() {
        if (ticksInState < clickDelayTicks) return Action.NONE;
        if (marketClickAttempts < maxMarketClickAttempts) {
            transition(State.WAITING_AFTER_LOADING_CLICK);
            return Action.NONE;
        }
        return requestReconnect();
    }

    /**
     * Wait for the reconnect cooldown to finish. If it has finished, reset the click attempts and move back to waiting for player.
     * @return Action to take next
     */
    private Action waitForReconnectCooldown() {
        if (ticksInState >= reconnectCooldownTicks) {
            loadingClickAttempts = 0;
            marketClickAttempts = 0;
            transition(State.WAITING_FOR_PLAYER);
        }
        return Action.NONE;
    }

    /**
     * Request a reconnect to the server. 
     * @return Action to take next
     */
    private Action requestReconnect() {
        transition(State.RECONNECT_COOLDOWN);
        return Action.REQUEST_RECONNECT;
    }

    /**
     * Transition to a new state and reset the ticks in that state. If the new state is the same as the current state, do nothing.
     * @param next
     */
    private void transition(State next) {
        if (state != next) {
            state = next;
            ticksInState = 0;
        }
    }

    public State state() { return state; }
    public int loadingClickAttempts() { return loadingClickAttempts; }
    public int marketClickAttempts() { return marketClickAttempts; }
}

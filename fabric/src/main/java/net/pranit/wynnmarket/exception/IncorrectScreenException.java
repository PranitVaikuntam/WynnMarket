package net.pranit.wynnmarket.exception;

public class IncorrectScreenException extends Exception {
    public IncorrectScreenException(String message) {
        super(message);
    }

    public IncorrectScreenException(String message, Throwable cause) {
        super(message, cause);
    }
}

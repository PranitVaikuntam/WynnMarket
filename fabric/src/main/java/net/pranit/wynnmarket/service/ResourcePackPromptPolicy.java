package net.pranit.wynnmarket.service;

import java.util.Locale;

final class ResourcePackPromptPolicy {
    private ResourcePackPromptPolicy() {}

    static boolean isResourcePackPrompt(String title) {
        String normalized = title.toLowerCase(Locale.ROOT);
        return normalized.contains("resource pack") || normalized.contains("texture pack");
    }

    static boolean isAcceptButton(String label) {
        String normalized = label.toLowerCase(Locale.ROOT);
        return normalized.contains("yes") || normalized.contains("accept")
            || normalized.contains("download") || normalized.contains("proceed");
    }
}

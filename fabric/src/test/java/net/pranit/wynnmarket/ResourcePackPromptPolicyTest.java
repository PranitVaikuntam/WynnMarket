package net.pranit.wynnmarket.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ResourcePackPromptPolicyTest {
    @Test void recognizesResourcePackPromptAndPositiveButtons() {
        assertTrue(ResourcePackPromptPolicy.isResourcePackPrompt("Server Resource Pack"));
        assertTrue(ResourcePackPromptPolicy.isResourcePackPrompt("Download Texture Pack?"));
        assertTrue(ResourcePackPromptPolicy.isAcceptButton("Proceed"));
        assertTrue(ResourcePackPromptPolicy.isAcceptButton("Yes"));
        assertFalse(ResourcePackPromptPolicy.isAcceptButton("Disconnect"));
        assertFalse(ResourcePackPromptPolicy.isResourcePackPrompt("Disconnected"));
    }
}

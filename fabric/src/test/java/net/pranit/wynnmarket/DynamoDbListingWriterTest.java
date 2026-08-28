package net.pranit.wynnmarket.service;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class DynamoDbListingWriterTest {
    @Test void continuesAfterIndividualWriteFailuresAndCountsThem() {
        int failures = DynamoDbListingWriter.countWriteFailures(
            List.of("ok", "fail", "also-ok"),
            value -> {
                if (value.equals("fail")) throw new IllegalStateException("simulated DynamoDB outage");
            }
        );

        assertEquals(1, failures);
    }
}

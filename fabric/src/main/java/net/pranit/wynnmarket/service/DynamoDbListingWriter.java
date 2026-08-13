package net.pranit.wynnmarket.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jdk8.Jdk8Module;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.wynnventory.model.item.trademarket.TrademarketListing;
import net.pranit.wynnmarket.WynnMarket;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.stream.IntStream;

public final class DynamoDbListingWriter {
    private static final String[] SIMPLE_ITEM_TYPES = {
        "SimulatorItem",
        "InsulatorItem",
        "RuneItem",
        "DungeonKeyItem",
        "EmeraldItem",
        "AspectItem",
        "TomeItem"
    };
    private static final String[] TIER_ITEM_TYPES = {
        "IngredientItem",
        "MaterialItem",
        "PowderItem",
        "AmplifierItem",
        "MountItem",
        "EmeraldPouchItem"
    };
    private static final String[] GEAR_ITEM_TYPES = {
        "GearItem"
    };

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper()
        .registerModule(new Jdk8Module())
        .registerModule(new JavaTimeModule())
        .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    private static final String DYNAMODB_TABLE_NAME = System.getenv().getOrDefault(
        "WYNNMARKET_DYNAMODB_TABLE",
        "wynnmarket-trade-market-listings"
    );
    private static final Region AWS_REGION = Region.of(System.getenv().getOrDefault(
        "WYNNMARKET_AWS_REGION",
        "us-east-1"
    ));
    private static final DynamoDbClient DYNAMODB_CLIENT = DynamoDbClient.builder()
        .region(AWS_REGION)
        .credentialsProvider(DefaultCredentialsProvider.create())
        .httpClientBuilder(UrlConnectionHttpClient.builder())
        .build();

    private DynamoDbListingWriter() {}

    /**
     * Filters the raw scan results and writes each listing to DynamoDB without blocking the render thread.
     */
    public static void sendListingsToDynamoDb(TrademarketListing[] rawListings) {
        List<Map<String, AttributeValue>> listingsToSend = new ArrayList<>();
        IntStream.range(0, rawListings.length)
            .filter(index -> rawListings[index] != null)
            .forEach(index ->
                addListingIfItPassesFilters(
                    rawListings[index],
                    index,
                    listingsToSend
                )
            );

        if (listingsToSend.isEmpty()) {
            WynnMarket.LOGGER.info("No new listings to send.");
            return;
        }

        CompletableFuture.runAsync(() -> {
            for (int index = 0; index < listingsToSend.size(); index++) {
                putListing(listingsToSend.get(index));
            }
        }).exceptionally(error -> {
            WynnMarket.LOGGER.error("Unable to write listings to DynamoDB", error);
            return null;
        });
    }

    private static void addListingIfItPassesFilters(
        TrademarketListing listing,
        int index,
        List<Map<String, AttributeValue>> listingsToSend
    ) {
        try {
            String listingJson = OBJECT_MAPPER.writeValueAsString(listing);
            JsonNode listingNode = OBJECT_MAPPER.readTree(listingJson);
            JsonNode itemNode = listingNode.path("item");

            Map<String, AttributeValue> listingPayload = new HashMap<>();
            String partitionKey = itemNode.get("itemType").asText();
            String sortKey = listingNode.get("timestamp").asText() + "_" + index;
            listingPayload.put("pk", AttributeValue.fromS(partitionKey));
            listingPayload.put("sk", AttributeValue.fromS(sortKey));
            listingPayload.put("amount", AttributeValue.fromN(listingNode.get("amount").asText()));
            listingPayload.put("listingPrice", AttributeValue.fromN(listingNode.get("listingPrice").asText()));

            Map<String, AttributeValue> itemPayload = new HashMap<>();
            if (hasItemType(partitionKey, SIMPLE_ITEM_TYPES)) {
                itemPayload = simpleFilter(itemNode);
            } else if (hasItemType(partitionKey, TIER_ITEM_TYPES)) {
                itemPayload = tierFilter(itemNode);
            } else if (hasItemType(partitionKey, GEAR_ITEM_TYPES)) {
                itemPayload = gearFilter(itemNode);
            } else {
                WynnMarket.LOGGER.warn("Skipping unsupported item type: {}", partitionKey);
                return;
            }
            listingPayload.put("item", AttributeValue.fromM(itemPayload));

            listingsToSend.add(listingPayload);
        } catch (JsonProcessingException e) {
            WynnMarket.LOGGER.error("Unable to filter listing before DynamoDB write", e);
        }
    }

    private static boolean hasItemType(String itemType, String[] acceptedItemTypes) {
        return Arrays.asList(acceptedItemTypes).contains(itemType);
    }

    private static Map<String, AttributeValue> simpleFilter(JsonNode itemNode) {
        Map<String, AttributeValue> itemPayload = new HashMap<>();
        itemPayload.put("name", AttributeValue.fromS(itemNode.get("name").asText()));
        itemPayload.put("rarity", AttributeValue.fromS(itemNode.get("rarity").asText()));
        itemPayload.put("itemType", AttributeValue.fromS(itemNode.get("itemType").asText()));
        itemPayload.put("type", AttributeValue.fromS(itemNode.get("type").asText()));

        return itemPayload;
    }

    private static Map<String, AttributeValue> tierFilter(JsonNode itemNode) {
        Map<String, AttributeValue> itemPayload = new HashMap<>();
        itemPayload.put("name", AttributeValue.fromS(itemNode.get("name").asText()));
        itemPayload.put("rarity", AttributeValue.fromS(itemNode.get("rarity").asText()));
        itemPayload.put("itemType", AttributeValue.fromS(itemNode.get("itemType").asText()));
        itemPayload.put("type", AttributeValue.fromS(itemNode.get("type").asText()));
        itemPayload.put("tier", AttributeValue.fromN(itemNode.get("tier").asText()));

        return itemPayload;
    }

    private static Map<String, AttributeValue> gearFilter(JsonNode itemNode) {
        Map<String, AttributeValue> itemPayload = new HashMap<>();
        itemPayload.put("name", AttributeValue.fromS(itemNode.get("name").asText()));
        itemPayload.put("rarity", AttributeValue.fromS(itemNode.get("rarity").asText()));
        itemPayload.put("itemType", AttributeValue.fromS(itemNode.get("itemType").asText()));
        itemPayload.put("type", AttributeValue.fromS(itemNode.get("type").asText()));

        return itemPayload;
    }



    private static void putListing(Map<String, AttributeValue> item) {
        try {
            PutItemRequest request = PutItemRequest.builder()
                .tableName(DYNAMODB_TABLE_NAME)
                .item(item)
                .build();

            DYNAMODB_CLIENT.putItem(request);
            WynnMarket.LOGGER.info("Wrote listing {} to DynamoDB.", item.get("sk").s());
        } catch (RuntimeException e) {
            WynnMarket.LOGGER.error("Unable to write listing to DynamoDB", e);
        }
    }
}

#!/usr/bin/env node
/**
 * Duplicates items from the live wynnmarket listings table into a brand-new
 * table (same pk/sk schema) until the new table has > TARGET_COUNT items.
 *
 * Source table is only ever scanned, never written to.
 *
 * Usage:
 *   node scripts/duplicate-listings-to-new-table.mjs
 *
 * Env overrides:
 *   SOURCE_TABLE   (default: wynnmarket-trade-market-listings)
 *   DEST_TABLE     (default: wynnmarket-trade-market-listings-new)
 *   AWS_REGION     (default: us-east-1)
 *   TARGET_COUNT   (default: 100000)
 */
import {
  DynamoDBClient,
  CreateTableCommand,
  DescribeTableCommand,
  ScanCommand,
  BatchWriteItemCommand,
} from "@aws-sdk/client-dynamodb";

const REGION = process.env.AWS_REGION || "us-east-1";
const SOURCE_TABLE = process.env.SOURCE_TABLE || "wynnmarket-trade-market-listings";
const DEST_TABLE = process.env.DEST_TABLE || "wynnmarket-trade-market-listings-new";
const TARGET_COUNT = Number(process.env.TARGET_COUNT || 100000);

const client = new DynamoDBClient({ region: REGION });

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function ensureDestTable() {
  try {
    await client.send(new DescribeTableCommand({ TableName: DEST_TABLE }));
    console.log(`Destination table "${DEST_TABLE}" already exists.`);
    return;
  } catch (err) {
    if (err.name !== "ResourceNotFoundException") throw err;
  }

  console.log(`Creating destination table "${DEST_TABLE}"...`);
  await client.send(
    new CreateTableCommand({
      TableName: DEST_TABLE,
      AttributeDefinitions: [
        { AttributeName: "pk", AttributeType: "S" },
        { AttributeName: "sk", AttributeType: "S" },
      ],
      KeySchema: [
        { AttributeName: "pk", KeyType: "HASH" },
        { AttributeName: "sk", KeyType: "RANGE" },
      ],
      BillingMode: "PAY_PER_REQUEST",
    })
  );

  // Wait for ACTIVE.
  for (;;) {
    const { Table } = await client.send(
      new DescribeTableCommand({ TableName: DEST_TABLE })
    );
    if (Table.TableStatus === "ACTIVE") break;
    await sleep(2000);
  }
  console.log(`Destination table "${DEST_TABLE}" is ACTIVE.`);
}

async function scanAllSourceItems() {
  const items = [];
  let ExclusiveStartKey;
  do {
    const result = await client.send(
      new ScanCommand({ TableName: SOURCE_TABLE, ExclusiveStartKey })
    );
    items.push(...(result.Items || []));
    ExclusiveStartKey = result.LastEvaluatedKey;
  } while (ExclusiveStartKey);
  return items;
}

function getTimestampRange(items) {
  let minMs = Infinity;
  let maxMs = -Infinity;
  for (const item of items) {
    const ts = item.timestamp?.S;
    if (!ts) continue;
    const ms = Date.parse(ts);
    if (Number.isNaN(ms)) continue;
    if (ms < minMs) minMs = ms;
    if (ms > maxMs) maxMs = ms;
  }
  if (!Number.isFinite(minMs) || !Number.isFinite(maxMs)) {
    const now = Date.now();
    return { minMs: now, maxMs: now };
  }
  return { minMs, maxMs };
}

// Builds a duplicate record: same pk/item, new sk, timestamp drawn uniformly
// at random from across the whole dataset's time range (not jittered around
// the source item's own timestamp) so repeated copies of the same item end
// up scattered through the browsing range instead of sitting next to each
// other.
function buildDuplicate(sourceItem, copyIndex, timestampRange) {
  const clone = structuredClone(sourceItem);

  const { minMs, maxMs } = timestampRange;
  const newMs = minMs + Math.random() * (maxMs - minMs);
  const newTimestamp = new Date(Math.round(newMs)).toISOString();

  clone.timestamp = { S: newTimestamp };
  // sk was originally "<timestamp>_<scanIndex>"; keep that shape, append a
  // dup-generation suffix so it stays unique within the pk partition.
  clone.sk = { S: `${newTimestamp}_dup${copyIndex}` };

  return clone;
}

async function batchWriteAll(items) {
  const BATCH_SIZE = 25;
  let written = 0;
  for (let i = 0; i < items.length; i += BATCH_SIZE) {
    const batch = items.slice(i, i + BATCH_SIZE);
    let requestItems = {
      [DEST_TABLE]: batch.map((item) => ({ PutRequest: { Item: item } })),
    };

    // Retry unprocessed items with backoff.
    let attempt = 0;
    while (Object.keys(requestItems).length > 0) {
      const result = await client.send(
        new BatchWriteItemCommand({ RequestItems: requestItems })
      );
      const unprocessed = result.UnprocessedItems || {};
      if (Object.keys(unprocessed).length === 0) break;
      attempt++;
      await sleep(Math.min(1000 * 2 ** attempt, 5000));
      requestItems = unprocessed;
    }

    written += batch.length;
    if (written % 1000 === 0) {
      console.log(`Written ${written}/${items.length} duplicate items...`);
    }
  }
  return written;
}

async function main() {
  await ensureDestTable();

  console.log(`Scanning source table "${SOURCE_TABLE}"...`);
  const sourceItems = await scanAllSourceItems();
  console.log(`Fetched ${sourceItems.length} source items.`);

  if (sourceItems.length === 0) {
    console.error("Source table is empty, nothing to duplicate.");
    process.exit(1);
  }

  // How many full passes over the source set are needed to clear the target,
  // plus one partial pass so we land just above it.
  const fullPasses = Math.floor(TARGET_COUNT / sourceItems.length);
  const remainder = TARGET_COUNT - fullPasses * sourceItems.length;
  const totalPasses = remainder > 0 ? fullPasses + 1 : fullPasses;

  const timestampRange = getTimestampRange(sourceItems);
  console.log(
    `Source timestamp range: ${new Date(timestampRange.minMs).toISOString()} -> ${new Date(timestampRange.maxMs).toISOString()}`
  );
  console.log(
    `Target ${TARGET_COUNT} items from ${sourceItems.length} source items -> ${totalPasses} duplication pass(es).`
  );

  let copyIndex = 0;
  let totalWritten = 0;
  for (let pass = 0; pass < totalPasses; pass++) {
    const duplicates = sourceItems.map((item) =>
      buildDuplicate(item, copyIndex++, timestampRange)
    );
    const written = await batchWriteAll(duplicates);
    totalWritten += written;
    console.log(
      `Pass ${pass + 1}/${totalPasses} complete. Total written so far: ${totalWritten}`
    );
  }

  console.log(`Done. Wrote ${totalWritten} duplicate items into "${DEST_TABLE}".`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

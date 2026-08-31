# WynnMarket web

The web app reads the existing `wynnmarket-trade-market-listings` DynamoDB table without changing it. On first request, the server performs a paginated projection-only scan, normalizes item names, keeps tiers separate, and builds an in-memory catalogue and history index. It then queries each known `pk` item-type partition for records newer than its last observed `sk`.

## Local development

Node.js 22 or newer is required.

```bash
npm ci
WYNNMARKET_USE_DEMO_DATA=true npm run dev
```

To use the live table, omit `WYNNMARKET_USE_DEMO_DATA` and use an existing AWS profile or instance role:

```bash
AWS_REGION=us-east-1 \
WYNNMARKET_DYNAMODB_TABLE=wynnmarket-trade-market-listings \
npm run dev
```

Copy `.env.example` to `.env.local` when persistent local values are useful. Do not place AWS credentials in that file; the AWS SDK automatically uses the normal credential chain.

## Validate and run

```bash
npm test
npm run lint
npm run build
HOST=0.0.0.0 PORT=3000 node dist/standalone/server.js
```

## EC2 container

Build from the repository root:

```bash
docker build -t wynnmarket-web:latest web
docker run -d \
  --name wynnmarket-web \
  --restart unless-stopped \
  -p 3000:3000 \
  -e AWS_REGION=us-east-1 \
  -e WYNNMARKET_DYNAMODB_TABLE=wynnmarket-trade-market-listings \
  -e WYNNMARKET_SITE_URL=https://market.example.com \
  wynnmarket-web:latest
```

The EC2 instance role needs only these read actions on the listings table:

```json
{
  "Effect": "Allow",
  "Action": [
    "dynamodb:DescribeTable",
    "dynamodb:Scan",
    "dynamodb:Query"
  ],
  "Resource": "arn:aws:dynamodb:us-east-1:<account-id>:table/wynnmarket-trade-market-listings"
}
```

Expose the container through the host's existing reverse proxy or load balancer. The app provides `/api/health` for container and load-balancer health checks. The current repository security group is outbound-only, so public deployment also requires an explicitly scoped inbound listener.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `AWS_REGION` | `us-east-1` | DynamoDB region |
| `WYNNMARKET_DYNAMODB_TABLE` | `wynnmarket-trade-market-listings` | Source table |
| `WYNNMARKET_REFRESH_SECONDS` | `60` | Incremental refresh interval; minimum 30 seconds |
| `WYNNMARKET_SITE_URL` | `http://localhost:3000` | Trusted public origin for social metadata |
| `WYNNMARKET_USE_DEMO_DATA` | `false` | Enables generated local development records |

The cache is process-local and rebuilds after a restart. That is appropriate for the current 7.3 MB table. If the dataset or traffic grows substantially, add a top-level normalized `itemKey` and a DynamoDB GSI keyed by `itemKey` and `sk`.

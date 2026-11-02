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

The repository-level deployment script is the recommended path. It uses SSM, clones or updates the repository on EC2, builds this Dockerfile there, and publishes the container on host port 80:

```bash
./scripts/deploy-web-to-ec2.sh main
```

To build manually from a checkout already on the EC2 host:

```bash
sudo AWS_REGION=us-east-1 \
  WYNNMARKET_DYNAMODB_TABLE=wynnmarket-trade-market-listings \
  ./scripts/run-web-on-ec2.sh
```

The web application requires these read actions on the EC2 instance role in addition to the collector's existing write permissions:

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

Terraform exposes HTTP port 80 through the EC2 security group. The container publishes host port 80 to its internal port 3000 and provides `/api/health` for its Docker health check. No SSH ingress is required.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `AWS_REGION` | `us-east-1` | DynamoDB region |
| `WYNNMARKET_DYNAMODB_TABLE` | `wynnmarket-trade-market-listings` | Source table |
| `WYNNMARKET_REFRESH_SECONDS` | `60` | Incremental refresh interval; minimum 30 seconds |
| `WYNNMARKET_SITE_URL` | `http://localhost:3000` | Trusted public origin for social metadata |
| `WYNNMARKET_USE_DEMO_DATA` | `false` | Enables generated local development records |

The cache is process-local and rebuilds after a restart. That is appropriate for the current 7.3 MB table. If the dataset or traffic grows substantially, add a top-level normalized `itemKey` and a DynamoDB GSI keyed by `itemKey` and `sk`.

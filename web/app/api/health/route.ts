import { marketCache } from '@/lib/market-cache';

export const dynamic = 'force-dynamic';

export async function GET() {
  const status = marketCache.getStatus();
  const ok = status.state !== 'error';
  return Response.json(
    { ok, market: { ...status, error: status.error ? 'Market refresh failed' : undefined } },
    { status: ok ? 200 : 503 },
  );
}

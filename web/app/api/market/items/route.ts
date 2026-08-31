import { marketCache } from '@/lib/market-cache';

export const dynamic = 'force-dynamic';

function publicStatus() {
  const status = marketCache.getStatus();
  return { ...status, error: status.error ? 'Market refresh delayed' : undefined };
}

export async function GET() {
  try {
    await marketCache.ensureReady();
    return Response.json(
      { items: marketCache.getCatalog(), status: publicStatus() },
      { headers: { 'Cache-Control': 'no-store' } },
    );
  } catch {
    return Response.json(
      { error: 'The market feed is temporarily unavailable.', status: publicStatus() },
      { status: 503, headers: { 'Cache-Control': 'no-store' } },
    );
  }
}

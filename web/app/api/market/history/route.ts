import { marketCache } from '@/lib/market-cache';
import type { HistoryRange } from '@/lib/market';

export const dynamic = 'force-dynamic';

const VALID_RANGES = new Set<HistoryRange>(['24h', '7d', '30d', 'all']);

export async function GET(request: Request) {
  const url = new URL(request.url);
  const id = url.searchParams.get('id')?.trim() ?? '';
  const requestedRange = url.searchParams.get('range') as HistoryRange | null;
  const range = requestedRange && VALID_RANGES.has(requestedRange) ? requestedRange : '7d';

  if (!id || id.length > 300) {
    return Response.json({ error: 'A valid item id is required.' }, { status: 400 });
  }

  try {
    await marketCache.ensureReady();
    const history = marketCache.getHistory(id, range);
    if (!history) return Response.json({ error: 'Item not found.' }, { status: 404 });
    return Response.json(history, { headers: { 'Cache-Control': 'no-store' } });
  } catch {
    return Response.json(
      { error: 'The market feed is temporarily unavailable.' },
      { status: 503, headers: { 'Cache-Control': 'no-store' } },
    );
  }
}

'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import type { CacheStatus } from '@/lib/market-cache';
import type { CatalogItem, HistoryPoint, HistoryRange, ItemHistory } from '@/lib/market';

interface CatalogResponse {
  items: CatalogItem[];
  status: CacheStatus;
  error?: string;
}

const RANGE_LABELS: { value: HistoryRange; label: string }[] = [
  { value: '24h', label: '24H' },
  { value: '7d', label: '7D' },
  { value: '30d', label: '30D' },
  { value: 'all', label: 'ALL' },
];

const numberFormatter = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });

function formatPrice(value: number): string {
  return numberFormatter.format(value);
}

function formatDateTime(value: string): string {
  if (!value) return '—';
  return new Intl.DateTimeFormat(undefined, {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  }).format(new Date(value));
}

function timeAgo(value: string): string {
  if (!value) return 'waiting for data';
  const difference = Date.now() - Date.parse(value);
  if (!Number.isFinite(difference)) return 'recently';
  const minutes = Math.max(0, Math.floor(difference / 60_000));
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

function tierLabel(tier?: number): string {
  return tier === undefined ? '' : ` · Tier ${tier}`;
}

async function fetchCatalog(): Promise<CatalogResponse> {
  const response = await fetch('/api/market/items', { cache: 'no-store' });
  const payload = await response.json() as CatalogResponse;
  if (!response.ok) throw new Error(payload.error ?? 'Unable to load the market catalogue.');
  return payload;
}

function PriceChart({ points }: { points: HistoryPoint[] }) {
  if (points.length === 0) {
    return <div className="empty-chart">No observations in this time range.</div>;
  }

  const width = 648;
  const height = 96;
  const allPrices = points.flatMap((point) => [point.lowestPrice, point.highestPrice]);
  const rawMin = Math.min(...allPrices);
  const rawMax = Math.max(...allPrices);
  const pricePadding = Math.max((rawMax - rawMin) * 0.12, rawMax * 0.025, 1);
  const minPrice = Math.max(0, rawMin - pricePadding);
  const maxPrice = rawMax + pricePadding;
  const priceSpan = Math.max(maxPrice - minPrice, 1);
  const coordinate = (point: HistoryPoint, index: number) => ({
    x: points.length === 1 ? width / 2 : (index / (points.length - 1)) * width,
    y: height - ((point.medianPrice - minPrice) / priceSpan) * height,
  });
  const coordinates = points.map(coordinate);
  const path = coordinates.map(({ x, y }, index) => `${index === 0 ? 'M' : 'L'} ${x} ${y}`).join(' ');
  const areaPath = `${path} L ${coordinates.at(-1)!.x} ${height} L ${coordinates[0].x} ${height} Z`;
  const yTicks = Array.from({ length: 4 }, (_, index) =>
    Math.round(maxPrice - (index / 3) * priceSpan),
  );
  const labelIndexes = [...new Set([0, Math.floor((points.length - 1) / 3), Math.floor(((points.length - 1) * 2) / 3), points.length - 1])];
  const pointStep = Math.max(1, Math.ceil(points.length / 28));

  return (
    <div className="chart-frame">
      <div className="y-axis" aria-hidden="true">
        {yTicks.map((tick) => <span key={tick}>{formatPrice(tick)}</span>)}
      </div>
      <div className="chart-plot">
        <div className="chart-grid" aria-hidden="true" />
        <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" role="img" aria-label="Median observed listing price over time">
          <path className="area-fill" d={areaPath} />
          <path className="price-line" d={path} />
          {coordinates.map(({ x, y }, index) => (
            index % pointStep === 0 || index === points.length - 1
              ? (
                <circle key={points[index].timestamp} cx={x} cy={y} r={index === points.length - 1 ? 4.5 : 2.6} tabIndex={0}>
                  <title>{`${formatDateTime(points[index].timestamp)} — median ${formatPrice(points[index].medianPrice)} emeralds (${points[index].observationCount} observations)`}</title>
                </circle>
              )
              : null
          ))}
        </svg>
        <div className="x-axis" aria-hidden="true">
          {labelIndexes.map((index) => <span key={points[index].timestamp}>{formatDateTime(points[index].timestamp)}</span>)}
        </div>
      </div>
    </div>
  );
}

export default function Home() {
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [cacheStatus, setCacheStatus] = useState<CacheStatus | null>(null);
  const [selectedId, setSelectedId] = useState('');
  const [selectedType, setSelectedType] = useState('all');
  const [search, setSearch] = useState('');
  const [range, setRange] = useState<HistoryRange>('7d');
  const [history, setHistory] = useState<ItemHistory | null>(null);
  const [catalogLoading, setCatalogLoading] = useState(true);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [error, setError] = useState('');
  const searchRef = useRef<HTMLInputElement>(null);

  const loadCatalog = async () => {
    try {
      const payload = await fetchCatalog();
      setItems(payload.items);
      setCacheStatus(payload.status);
      if (!selectedId && payload.items[0]?.id) {
        setHistoryLoading(true);
        setSelectedId(payload.items[0].id);
      }
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Unable to load the market catalogue.');
    } finally {
      setCatalogLoading(false);
    }
  };

  useEffect(() => {
    let cancelled = false;
    void fetchCatalog()
      .then((payload) => {
        if (cancelled) return;
        setItems(payload.items);
        setCacheStatus(payload.status);
        if (payload.items[0]?.id) {
          setHistoryLoading(true);
          setSelectedId(payload.items[0].id);
        }
      })
      .catch((loadError: unknown) => {
        if (!cancelled) setError(loadError instanceof Error ? loadError.message : 'Unable to load the market catalogue.');
      })
      .finally(() => {
        if (!cancelled) setCatalogLoading(false);
      });
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    const focusSearch = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLocaleLowerCase() === 'k') {
        event.preventDefault();
        searchRef.current?.focus();
      }
    };
    window.addEventListener('keydown', focusSearch);
    return () => window.removeEventListener('keydown', focusSearch);
  }, []);

  useEffect(() => {
    if (!selectedId) return;
    const controller = new AbortController();
    const loadHistory = async () => {
      try {
        const parameters = new URLSearchParams({ id: selectedId, range });
        const response = await fetch(`/api/market/history?${parameters}`, {
          cache: 'no-store', signal: controller.signal,
        });
        const payload = await response.json() as ItemHistory & { error?: string };
        if (!response.ok) throw new Error(payload.error ?? 'Unable to load this item’s history.');
        setHistory(payload);
      } catch (loadError) {
        if (loadError instanceof DOMException && loadError.name === 'AbortError') return;
        setError(loadError instanceof Error ? loadError.message : 'Unable to load this item’s history.');
      } finally {
        if (!controller.signal.aborted) setHistoryLoading(false);
      }
    };
    void loadHistory();
    return () => controller.abort();
  }, [selectedId, range]);

  const itemTypes = useMemo(() => {
    const labels = new Map(items.map((item) => [item.itemType, item.itemTypeLabel]));
    return [...labels.entries()].sort((left, right) => left[1].localeCompare(right[1]));
  }, [items]);

  const filteredItems = useMemo(() => {
    const normalizedSearch = search.trim().toLocaleLowerCase();
    return items.filter((item) =>
      (selectedType === 'all' || item.itemType === selectedType)
      && (!normalizedSearch
        || item.name.toLocaleLowerCase().includes(normalizedSearch)
        || item.itemTypeLabel.toLocaleLowerCase().includes(normalizedSearch)
        || item.type?.toLocaleLowerCase().includes(normalizedSearch)),
    );
  }, [items, search, selectedType]);

  const visibleItems = filteredItems.slice(0, 100);
  const selectedItem = items.find((item) => item.id === selectedId);
  const summary = history?.summary;
  const change = summary?.changeFromMedianPercent ?? 0;
  const feedHealthy = cacheStatus?.state === 'ready' && !cacheStatus.error;

  return (
    <main className="app-shell">
      <header className="topbar">
        <a className="brand" href="#" aria-label="WynnMarket home">
          <span className="brand-mark" aria-hidden="true">W</span>
          <span><strong>WYNNMARKET</strong><small>Trade intelligence</small></span>
        </a>
        <div className={`market-status ${feedHealthy ? '' : 'is-loading'}`} role="status">
          <span className="status-dot" aria-hidden="true" />
          {catalogLoading ? 'Indexing market feed' : feedHealthy ? 'Market feed live' : 'Feed unavailable'}
          <span className="status-time">
            {cacheStatus?.lastRefreshAt ? `updated ${timeAgo(cacheStatus.lastRefreshAt)}` : 'connecting'}
          </span>
        </div>
      </header>

      <div className="workspace">
        <aside className="item-panel" aria-label="Item browser">
          <div className="panel-heading">
            <div><p className="eyebrow">Market index</p><h2>Find an item</h2></div>
            <span className="item-count">{catalogLoading ? '…' : filteredItems.length}</span>
          </div>

          <label className="search-box">
            <span aria-hidden="true">⌕</span>
            <input
              ref={searchRef}
              type="search"
              placeholder="Search market items"
              aria-label="Search market items"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
            <kbd>⌘K</kbd>
          </label>

          <label className="type-select">
            <span>Item type</span>
            <select value={selectedType} onChange={(event) => setSelectedType(event.target.value)}>
              <option value="all">All market items</option>
              {itemTypes.map(([value, label]) => <option key={value} value={value}>{label}s</option>)}
            </select>
          </label>

          <div className="item-list" role="listbox" aria-label="Items" aria-busy={catalogLoading}>
            {catalogLoading && Array.from({ length: 6 }, (_, index) => <div className="item-skeleton" key={index} />)}
            {!catalogLoading && visibleItems.map((item) => (
              <button
                className={`item-row ${item.id === selectedId ? 'is-active' : ''}`}
                key={item.id}
                role="option"
                aria-selected={item.id === selectedId}
                onClick={() => {
                  setHistoryLoading(true);
                  setError('');
                  setSelectedId(item.id);
                }}
              >
                <span className="item-glyph" aria-hidden="true">{item.name.charAt(0)}</span>
                <span className="item-copy">
                  <strong>{item.name}</strong>
                  <small>{item.itemTypeLabel}{tierLabel(item.tier)}</small>
                </span>
                <span className="item-price">
                  <strong>{formatPrice(item.latestPrice)}</strong>
                  <small>emeralds</small>
                </span>
              </button>
            ))}
            {!catalogLoading && filteredItems.length === 0 && <p className="empty-list">No matching market items.</p>}
          </div>

          {!catalogLoading && filteredItems.length > visibleItems.length && (
            <p className="panel-note">Showing the first {visibleItems.length} matches. Refine your search to narrow the list.</p>
          )}
          {!catalogLoading && filteredItems.length <= visibleItems.length && (
            <p className="panel-note">{items.length} variants indexed from {formatPrice(cacheStatus?.recordCount ?? 0)} observations.</p>
          )}
        </aside>

        <section className="market-detail" aria-busy={historyLoading}>
          {error && (
            <div className="error-banner" role="alert">
              <span>{error}</span>
              {!selectedItem && <button type="button" onClick={() => { setCatalogLoading(true); setError(''); void loadCatalog(); }}>Try again</button>}
            </div>
          )}

          {!selectedItem && !catalogLoading ? (
            <div className="empty-detail"><p className="eyebrow">Market index</p><h1>Select an item</h1><p>Choose a market item to explore its observed price history.</p></div>
          ) : (
            <>
              <div className="detail-heading">
                <div>
                  <div className="crumbs"><span>{selectedItem?.itemTypeLabel ?? 'Market'}</span><b>/</b><span>{selectedItem?.rarity ?? 'Observed'}</span></div>
                  <h1>
                    {selectedItem?.name ?? 'Loading market'}
                    {selectedItem?.tier !== undefined && <span>T{selectedItem.tier}</span>}
                  </h1>
                  <p>
                    {selectedItem ? `${selectedItem.itemTypeLabel}${tierLabel(selectedItem.tier)} · ${formatPrice(selectedItem.observationCount)} total observations` : 'Building the item catalogue…'}
                  </p>
                </div>
                <div className="last-seen"><span>Last observed</span><strong>{selectedItem ? timeAgo(selectedItem.lastSeen) : '—'}</strong></div>
              </div>

              <div className="metric-grid">
                <article className="metric primary-metric">
                  <span>Latest observed</span>
                  <strong>{summary ? formatPrice(summary.latestPrice) : '—'} <small>e</small></strong>
                  <p className={change > 0 ? 'negative-change' : ''}>
                    {summary && summary.observationCount > 0
                      ? <><b>{change > 0 ? '↑' : '↓'} {Math.abs(change).toFixed(1)}%</b> from range median</>
                      : 'No observations in this range'}
                  </p>
                </article>
                <article className="metric">
                  <span>Range low</span>
                  <strong>{summary ? formatPrice(summary.lowestPrice) : '—'} <small>e</small></strong>
                  <p>{summary ? `${formatPrice(summary.observationCount)} listing observations` : 'Loading history'}</p>
                </article>
                <article className="metric">
                  <span>Observed volume</span>
                  <strong>{summary ? formatPrice(summary.observedVolume) : '—'}</strong>
                  <p>Units seen in the selected range</p>
                </article>
              </div>

              <article className="chart-card">
                <div className="chart-heading">
                  <div><p className="eyebrow">Price history</p><h2>Market pulse</h2></div>
                  <div className="range-picker" aria-label="Chart time range">
                    {RANGE_LABELS.map((option) => (
                      <button
                        className={range === option.value ? 'active' : ''}
                        type="button"
                        aria-pressed={range === option.value}
                        onClick={() => {
                          setHistoryLoading(true);
                          setError('');
                          setRange(option.value);
                        }}
                        key={option.value}
                      >{option.label}</button>
                    ))}
                  </div>
                </div>

                {historyLoading ? <div className="chart-loading" aria-label="Loading price history" /> : <PriceChart points={history?.series ?? []} />}

                <div className="chart-legend">
                  <span><i className="legend-line" /> Median listing price</span>
                  <span><i className="legend-dot" /> Latest: {summary ? formatPrice(summary.latestPrice) : '—'} e</span>
                </div>
              </article>

              <article className="activity-card">
                <div className="activity-heading">
                  <div><p className="eyebrow">Fresh observations</p><h2>Recent listings</h2></div>
                  <span>Your local time</span>
                </div>
                <div className="listing-table" role="table" aria-label="Recent listing observations">
                  <div className="listing-row listing-header" role="row">
                    <span role="columnheader">Observed</span><span role="columnheader">Amount</span><span role="columnheader">Price</span>
                  </div>
                  {(history?.recent ?? []).slice(0, 5).map((observation, index) => (
                    <div className="listing-row" role="row" key={`${observation.timestamp}-${index}`}>
                      <span role="cell">{formatDateTime(observation.timestamp)}</span>
                      <span role="cell">{formatPrice(observation.amount)} {observation.amount === 1 ? 'unit' : 'units'}</span>
                      <span role="cell">{formatPrice(observation.price)} e</span>
                    </div>
                  ))}
                  {!historyLoading && (history?.recent.length ?? 0) === 0 && <p className="empty-list">No recent observations for this range.</p>}
                </div>
              </article>
            </>
          )}
        </section>
      </div>
    </main>
  );
}

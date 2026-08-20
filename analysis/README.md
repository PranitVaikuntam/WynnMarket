# Market price forecasting

`market_price_model.py` decodes the raw DynamoDB scan, groups listings into
five-minute market snapshots, analyzes the available history, and trains three
CatBoost quantile models. The output is a low, median, and high forecast for
each item variant.

`dashboard.py` adds item selection, price and supply history, fair-value
comparison, model confidence ranges, and a read-only market refresh action.

```bash
python3 -m pip install -r analysis/requirements.txt
analysis/.venv/bin/python analysis/market_price_model.py --analyze-only
analysis/.venv/bin/python analysis/market_price_model.py
analysis/.venv/bin/streamlit run analysis/dashboard.py
```

Place a DynamoDB scan export at
`analysis/data/trade_market_listings.json`. Outputs are written to
`analysis/output/`:

- `analysis.json`: dataset coverage and price summary
- `metadata.json`: chronological backtest metrics and feature definitions
- `price_low.cbm`, `price_median.cbm`, `price_high.cbm`: trained models
- `forecasts.csv`: next-period forecasts for all observed item variants

The current table contains less than two days of history. Backtest metrics are
therefore more useful than the apparent training fit, and forecasts should not
be treated as stable until several weeks of data have accumulated.

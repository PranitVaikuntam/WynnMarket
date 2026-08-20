#!/usr/bin/env python3
"""Interactive WynnMarket price history and fair-value dashboard."""

from __future__ import annotations

import os
import statistics
import subprocess
import sys
import tempfile
from datetime import timedelta
from pathlib import Path

import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from plotly.subplots import make_subplots

from market_price_model import aggregate_snapshots, load_records


ANALYSIS_DIR = Path(__file__).resolve().parent
DATA_PATH = ANALYSIS_DIR / "data" / "trade_market_listings.json"
OUTPUT_DIR = ANALYSIS_DIR / "output"
FORECAST_PATH = OUTPUT_DIR / "forecasts.csv"
METADATA_PATH = OUTPUT_DIR / "metadata.json"
TABLE_NAME = "wynnmarket-trade-market-listings"
AWS_REGION = "us-east-1"


st.set_page_config(
    page_title="WynnMarket Price Desk",
    page_icon="WM",
    layout="wide",
    initial_sidebar_state="expanded",
)

st.markdown(
    """
    <style>
    :root {
        --ink: #20251f;
        --muted: #6d746b;
        --line: #dfe3dc;
        --paper: #f7f8f5;
        --green: #16735a;
        --amber: #b96f16;
        --red: #b1473f;
    }
    .stApp { background: var(--paper); color: var(--ink); }
    [data-testid="stHeader"] { background: transparent; }
    [data-testid="stSidebar"] { background: #eef1eb; border-right: 1px solid var(--line); }
    [data-testid="stSidebar"] hr { border-color: #d7dcd3; }
    [data-testid="stMetric"] {
        background: #ffffff;
        border: 1px solid var(--line);
        border-radius: 6px;
        padding: 14px 16px;
        min-height: 112px;
    }
    [data-testid="stMetricLabel"] { color: var(--muted); }
    [data-testid="stMetricValue"] { color: var(--ink); font-size: 1.65rem; }
    .market-kicker {
        color: var(--green);
        font-size: 0.76rem;
        font-weight: 700;
        text-transform: uppercase;
        margin-bottom: 5px;
    }
    .market-title { font-size: 1.9rem; font-weight: 760; line-height: 1.15; color: var(--ink); }
    .market-subtitle { color: var(--muted); font-size: 0.93rem; margin-top: 5px; }
    .status-line { text-align: right; color: var(--muted); font-size: 0.82rem; padding-top: 10px; }
    .method-strip {
        border-left: 3px solid var(--green);
        padding: 9px 12px;
        background: #f0f5f1;
        color: #3d493f;
        font-size: 0.88rem;
        margin: 4px 0 16px;
    }
    .section-label {
        color: var(--muted);
        font-size: 0.76rem;
        font-weight: 700;
        text-transform: uppercase;
        margin: 16px 0 4px;
    }
    div[data-testid="stDataFrame"] { border: 1px solid var(--line); border-radius: 6px; overflow: hidden; }
    .stPlotlyChart { background: #ffffff; border: 1px solid var(--line); border-radius: 6px; }
    button[kind="primary"] { border-radius: 5px; }
    @media (max-width: 800px) {
        .market-title { font-size: 1.5rem; }
        .status-line { text-align: left; }
        [data-testid="stMetric"] { min-height: 96px; }
    }
    </style>
    """,
    unsafe_allow_html=True,
)


def format_price(value: float) -> str:
    value = float(value)
    if value >= 1_000_000:
        return f"{value / 1_000_000:.2f}m"
    if value >= 10_000:
        return f"{value / 1_000:.1f}k"
    return f"{value:,.0f}"


def variant_label(row: pd.Series) -> str:
    tier = f"T{int(row['tier'])}" if int(row["tier"]) > 0 else "No tier"
    return f"{row['name']}  ·  {tier}  ·  {row['rarity']}"


@st.cache_data(show_spinner=False)
def load_market_data(data_path: str, data_mtime: float) -> pd.DataFrame:
    del data_mtime
    snapshots = aggregate_snapshots(load_records(Path(data_path)), 5)
    rows = []
    for snapshot in snapshots:
        item_type, type_name, name, rarity, tier = snapshot.variant
        rows.append(
            {
                "timestamp": snapshot.timestamp,
                "variant": "|".join(map(str, snapshot.variant)),
                "item_type": item_type,
                "type": type_name,
                "name": name,
                "rarity": rarity,
                "tier": tier,
                "price": snapshot.price,
                "quantity": snapshot.total_quantity,
                "listings": snapshot.listing_count,
                "minimum": snapshot.minimum_price,
                "maximum": snapshot.maximum_price,
            }
        )
    return pd.DataFrame(rows).sort_values(["timestamp", "variant"])


@st.cache_data(show_spinner=False)
def load_forecasts(path: str, mtime: float) -> pd.DataFrame:
    del mtime
    return pd.read_csv(path).set_index("variant")


@st.cache_data(show_spinner=False)
def load_metadata(path: str, mtime: float) -> dict:
    del mtime
    return pd.read_json(path, typ="series").to_dict()


def refresh_market() -> None:
    DATA_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    temporary_name = None
    try:
        with tempfile.NamedTemporaryFile(dir=DATA_PATH.parent, suffix=".json", delete=False) as temporary:
            temporary_name = temporary.name
            subprocess.run(
                [
                    "aws",
                    "dynamodb",
                    "scan",
                    "--table-name",
                    TABLE_NAME,
                    "--region",
                    AWS_REGION,
                    "--output",
                    "json",
                ],
                stdout=temporary,
                stderr=subprocess.PIPE,
                check=True,
                timeout=180,
            )
        os.replace(temporary_name, DATA_PATH)
        temporary_name = None
        subprocess.run(
            [sys.executable, str(ANALYSIS_DIR / "market_price_model.py")],
            capture_output=True,
            text=True,
            check=True,
            timeout=600,
        )
    finally:
        if temporary_name:
            Path(temporary_name).unlink(missing_ok=True)


def market_chart(history: pd.DataFrame, fair_price: float, low_price: float, high_price: float) -> go.Figure:
    chart = make_subplots(specs=[[{"secondary_y": True}]])
    chart.add_trace(
        go.Scatter(
            x=pd.concat([history["timestamp"], history["timestamp"].iloc[::-1]]),
            y=pd.concat([history["maximum"], history["minimum"].iloc[::-1]]),
            fill="toself",
            fillcolor="rgba(185, 111, 22, 0.10)",
            line={"color": "rgba(0,0,0,0)"},
            hoverinfo="skip",
            name="Listed range",
        ),
        secondary_y=False,
    )
    chart.add_trace(
        go.Bar(
            x=history["timestamp"],
            y=history["quantity"],
            marker_color="rgba(74, 99, 112, 0.17)",
            name="Supply",
            hovertemplate="%{y:,.0f} units<extra>Supply</extra>",
        ),
        secondary_y=True,
    )
    chart.add_trace(
        go.Scatter(
            x=history["timestamp"],
            y=history["price"],
            mode="lines+markers",
            line={"color": "#16735a", "width": 2.5},
            marker={"size": 5, "color": "#16735a"},
            name="Market price",
            hovertemplate="%{x|%b %d, %H:%M}<br>%{y:,.0f}<extra>Market price</extra>",
        ),
        secondary_y=False,
    )
    chart.add_hrect(y0=low_price, y1=high_price, fillcolor="rgba(22, 115, 90, 0.08)", line_width=0)
    chart.add_hline(y=fair_price, line={"color": "#b96f16", "width": 2, "dash": "dot"})
    chart.update_layout(
        height=430,
        margin={"l": 16, "r": 16, "t": 24, "b": 10},
        paper_bgcolor="#ffffff",
        plot_bgcolor="#ffffff",
        hovermode="x unified",
        bargap=0.35,
        legend={"orientation": "h", "yanchor": "bottom", "y": 1.02, "x": 0},
        font={"family": "Inter, ui-sans-serif, system-ui", "color": "#3d433c"},
    )
    chart.update_xaxes(showgrid=False, title=None)
    chart.update_yaxes(showgrid=True, gridcolor="#edf0eb", tickformat="~s", title=None, secondary_y=False)
    chart.update_yaxes(showgrid=False, visible=False, secondary_y=True)
    return chart


if not DATA_PATH.exists() or not FORECAST_PATH.exists() or not METADATA_PATH.exists():
    st.error("Market data or trained model output is missing.")
    st.code("analysis/venv/bin/python analysis/market_price_model.py")
    st.stop()

market = load_market_data(str(DATA_PATH), DATA_PATH.stat().st_mtime)
forecasts = load_forecasts(str(FORECAST_PATH), FORECAST_PATH.stat().st_mtime)
metadata = load_metadata(str(METADATA_PATH), METADATA_PATH.stat().st_mtime)
metrics = metadata["metrics"]

latest_items = market.sort_values("timestamp").groupby("variant", as_index=False).tail(1).copy()
latest_items["label"] = latest_items.apply(variant_label, axis=1)

with st.sidebar:
    st.markdown("### WynnMarket")
    st.caption("PRICE ANALYSIS")
    st.divider()
    categories = ["All"] + sorted(latest_items["item_type"].unique().tolist())
    category = st.selectbox("Category", categories)
    filtered_items = latest_items if category == "All" else latest_items[latest_items["item_type"] == category]
    rarities = ["All"] + sorted(filtered_items["rarity"].unique().tolist())
    rarity = st.selectbox("Rarity", rarities)
    if rarity != "All":
        filtered_items = filtered_items[filtered_items["rarity"] == rarity]
    filtered_items = filtered_items.sort_values(["name", "tier"])
    label_to_variant = dict(zip(filtered_items["label"], filtered_items["variant"]))
    selected_label = st.selectbox("Item", list(label_to_variant), index=0)
    selected_variant = label_to_variant[selected_label]
    st.divider()
    range_name = st.segmented_control("History", ["12h", "24h", "All"], default="All")
    if st.button("Refresh market & model", icon=":material/refresh:", width="stretch"):
        with st.status("Refreshing listings and retraining...", expanded=True) as status:
            try:
                refresh_market()
                st.cache_data.clear()
                status.update(label="Market and model refreshed", state="complete")
                st.rerun()
            except (subprocess.SubprocessError, OSError) as error:
                status.update(label="Refresh failed", state="error")
                st.error(str(error))
    st.caption(f"{len(filtered_items):,} selectable variants")

selected = latest_items[latest_items["variant"] == selected_variant].iloc[0]
full_history = market[market["variant"] == selected_variant].sort_values("timestamp").copy()
history = full_history.copy()
if range_name != "All":
    hours = 12 if range_name == "12h" else 24
    history = history[history["timestamp"] >= history["timestamp"].max() - timedelta(hours=hours)]

forecast = forecasts.loc[selected_variant]
model_fair = float(forecast["predicted_price"])
recent_prices = full_history["price"].tail(20)
baseline_fair = float(recent_prices.median())
baseline_wins = metrics["baseline_median_absolute_percentage_error"] <= metrics["model_median_absolute_percentage_error"]
if baseline_wins:
    fair_price = baseline_fair
    low_price = float(recent_prices.quantile(0.1))
    high_price = float(recent_prices.quantile(0.9))
    active_method = "Rolling market median"
    active_error = metrics["baseline_median_absolute_percentage_error"]
else:
    fair_price = model_fair
    low_price = float(forecast["low_price"])
    high_price = float(forecast["high_price"])
    active_method = "CatBoost quantile model"
    active_error = metrics["model_median_absolute_percentage_error"]

current_price = float(selected["price"])
price_delta = (current_price / fair_price - 1) * 100 if fair_price else 0
previous_price = float(full_history["price"].iloc[-2]) if len(full_history) > 1 else current_price
recent_delta = (current_price / previous_price - 1) * 100 if previous_price else 0
valuation_label = "At fair" if abs(price_delta) < 0.05 else ("Above fair" if price_delta > 0 else "Below fair")

header_left, header_right = st.columns([4, 1])
with header_left:
    st.markdown('<div class="market-kicker">Market intelligence</div>', unsafe_allow_html=True)
    st.markdown(f'<div class="market-title">{selected["name"]}</div>', unsafe_allow_html=True)
    st.markdown(
        f'<div class="market-subtitle">{selected["rarity"]} · Tier {int(selected["tier"])} · {selected["item_type"]}</div>',
        unsafe_allow_html=True,
    )
with header_right:
    updated = market["timestamp"].max().strftime("%b %d, %H:%M UTC")
    st.markdown(f'<div class="status-line">Updated<br><strong>{updated}</strong></div>', unsafe_allow_html=True)

st.markdown(
    f'<div class="method-strip"><strong>{active_method}</strong> is currently selected by chronological validation '
    f'({active_error:.1%} median error). Fair value uses {int(forecast["history_count"])} prior observations.</div>',
    unsafe_allow_html=True,
)

metric_columns = st.columns(4)
metric_columns[0].metric("Fair price", format_price(fair_price), f"Range {format_price(low_price)}–{format_price(high_price)}", delta_color="off")
metric_columns[1].metric("Latest market", format_price(current_price), f"{recent_delta:+.1f}% last reading")
metric_columns[2].metric("Vs. fair value", f"{price_delta:+.1f}%", valuation_label, delta_color="off")
metric_columns[3].metric("Available supply", f"{int(selected['quantity']):,}", f"{int(selected['listings'])} listings", delta_color="off")

st.markdown('<div class="section-label">Price history and listed supply</div>', unsafe_allow_html=True)
st.plotly_chart(
    market_chart(history, fair_price, low_price, high_price),
    width="stretch",
    config={"displayModeBar": False, "responsive": True},
)

comparison, recent = st.columns([1, 1.65], gap="large")
with comparison:
    st.markdown('<div class="section-label">Estimator comparison</div>', unsafe_allow_html=True)
    comparison_rows = pd.DataFrame(
        [
            {"Estimator": "Rolling median", "Fair price": format_price(baseline_fair), "Validation error": f"{metrics['baseline_median_absolute_percentage_error']:.1%}"},
            {"Estimator": "CatBoost", "Fair price": format_price(model_fair), "Validation error": f"{metrics['model_median_absolute_percentage_error']:.1%}"},
        ]
    )
    st.dataframe(comparison_rows, hide_index=True, width="stretch")
    st.caption(f"Backtest: {metrics['test_observations']:,} observations after {metrics['split_timestamp'][:16].replace('T', ' ')} UTC")
with recent:
    st.markdown('<div class="section-label">Recent market snapshots</div>', unsafe_allow_html=True)
    recent_rows = history.tail(10).iloc[::-1].copy()
    recent_rows["Time"] = recent_rows["timestamp"].dt.strftime("%b %d %H:%M")
    recent_rows["Market price"] = recent_rows["price"].map(format_price)
    recent_rows["Listed range"] = recent_rows.apply(lambda row: f"{format_price(row['minimum'])}–{format_price(row['maximum'])}", axis=1)
    recent_rows["Supply"] = recent_rows["quantity"].map(lambda value: f"{int(value):,}")
    st.dataframe(
        recent_rows[["Time", "Market price", "Listed range", "Supply"]],
        hide_index=True,
        width="stretch",
        height=350,
    )

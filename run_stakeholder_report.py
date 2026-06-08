from csv import DictWriter
from html import escape
from pathlib import Path

import duckdb


BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "case.duckdb"
REPORT_SQL_PATH = BASE_DIR / "sql" / "06_stakeholder_report.sql"
OUTPUT_DIR = BASE_DIR / "outputs"
REPORT_DIR = BASE_DIR / "reports"
REPORT_PATH = REPORT_DIR / "service_metrics_report.html"

REPORT_TABLES = [
    "report_kpis",
    "report_resolution_level",
    "report_account_ranking",
    "report_human_wait_by_team",
    "report_human_wait_by_agent",
    "report_key_insights",
]


def fetch_rows(con: duckdb.DuckDBPyConnection, table_name: str) -> list[dict]:
    relation = con.sql(f"select * from analytics.{table_name}")
    columns = [column[0] for column in relation.description]
    return [dict(zip(columns, row)) for row in relation.fetchall()]


def export_csv(rows: list[dict], path: Path) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return

    with path.open("w", newline="", encoding="utf-8") as file:
        writer = DictWriter(file, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def format_value(value: object) -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:,.2f}"
    return str(value)


def html_table(rows: list[dict], limit: int | None = None) -> str:
    visible_rows = rows[:limit] if limit else rows
    if not visible_rows:
        return "<p>Sem dados.</p>"

    columns = list(visible_rows[0].keys())
    header = "".join(f"<th>{escape(column)}</th>" for column in columns)
    body = []

    for row in visible_rows:
        cells = "".join(f"<td>{escape(format_value(row.get(column)))}</td>" for column in columns)
        body.append(f"<tr>{cells}</tr>")

    return f"<table><thead><tr>{header}</tr></thead><tbody>{''.join(body)}</tbody></table>"


def bar_chart(rows: list[dict], label_column: str, value_column: str, limit: int = 10) -> str:
    visible_rows = [row for row in rows if row.get(value_column) is not None][:limit]
    if not visible_rows:
        return "<p>Sem dados para o grafico.</p>"

    max_value = max(float(row[value_column]) for row in visible_rows) or 1.0
    bars = []

    for row in visible_rows:
        value = float(row[value_column])
        width = max(2, int((value / max_value) * 100))
        label = escape(str(row[label_column]))
        bars.append(
            f"""
            <div class="bar-row">
              <div class="bar-label">{label}</div>
              <div class="bar-track">
                <div class="bar-fill" style="width: {width}%"></div>
              </div>
              <div class="bar-value">{value:,.2f}</div>
            </div>
            """
        )

    return "".join(bars)


def build_html_report(data: dict[str, list[dict]]) -> str:
    kpis = data["report_kpis"][0]
    insights = data["report_key_insights"]
    account_rows = data["report_account_ranking"]
    resolution_rows = data["report_resolution_level"]
    team_rows = data["report_human_wait_by_team"]
    agent_rows = data["report_human_wait_by_agent"]

    insight_cards = "".join(
        f"""
        <article class="insight-card">
          <h3>{escape(row["insight_title"])}</h3>
          <p>{escape(row["insight_text"])}</p>
        </article>
        """
        for row in insights
    )

    kpi_cards = "".join(
        f"""
        <article class="kpi-card">
          <span>{escape(label)}</span>
          <strong>{escape(format_value(kpis[column]))}</strong>
        </article>
        """
        for label, column in [
            ("Conversas", "conversations"),
            ("Resolvidas", "resolved_conversations"),
            ("Reabertas", "reopened_conversations"),
            ("Resolucao media (min)", "avg_resolution_time_minutes"),
            ("Fila media (min)", "avg_queue_minutes"),
            ("Atendimento humano medio (min)", "avg_human_service_minutes"),
        ]
    )

    return f"""<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Service Time Metrics Report</title>
  <style>
    body {{
      margin: 0;
      font-family: Arial, sans-serif;
      color: #1f2937;
      background: #f8fafc;
    }}
    main {{
      max-width: 1180px;
      margin: 0 auto;
      padding: 32px 20px 56px;
    }}
    h1, h2, h3 {{
      margin: 0;
      color: #111827;
    }}
    h1 {{
      font-size: 32px;
      margin-bottom: 8px;
    }}
    h2 {{
      font-size: 22px;
      margin: 36px 0 16px;
    }}
    p {{
      line-height: 1.5;
    }}
    .subtitle {{
      margin: 0 0 24px;
      color: #4b5563;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
    }}
    .kpi-card, .insight-card {{
      background: white;
      border: 1px solid #e5e7eb;
      border-radius: 8px;
      padding: 16px;
    }}
    .kpi-card span {{
      display: block;
      color: #6b7280;
      font-size: 13px;
      margin-bottom: 8px;
    }}
    .kpi-card strong {{
      font-size: 24px;
    }}
    .insight-card h3 {{
      font-size: 16px;
      margin-bottom: 8px;
    }}
    .chart {{
      background: white;
      border: 1px solid #e5e7eb;
      border-radius: 8px;
      padding: 16px;
    }}
    .bar-row {{
      display: grid;
      grid-template-columns: minmax(180px, 260px) 1fr 80px;
      gap: 12px;
      align-items: center;
      margin: 10px 0;
      font-size: 13px;
    }}
    .bar-track {{
      height: 14px;
      background: #e5e7eb;
      border-radius: 999px;
      overflow: hidden;
    }}
    .bar-fill {{
      height: 100%;
      background: #2563eb;
    }}
    .bar-value {{
      text-align: right;
      color: #374151;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      background: white;
      border: 1px solid #e5e7eb;
      border-radius: 8px;
      overflow: hidden;
      font-size: 13px;
    }}
    th, td {{
      border-bottom: 1px solid #e5e7eb;
      padding: 10px;
      text-align: left;
      vertical-align: top;
    }}
    th {{
      background: #f3f4f6;
      color: #374151;
      font-weight: 700;
    }}
    @media (max-width: 760px) {{
      .bar-row {{
        grid-template-columns: 1fr;
      }}
      .bar-value {{
        text-align: left;
      }}
    }}
  </style>
</head>
<body>
  <main>
    <h1>Service Time Metrics</h1>
    <p class="subtitle">Relatorio visual para acompanhar tempo de resolucao, fila, atendimento, IA vs humano e escalonamento humano.</p>

    <section class="grid">{kpi_cards}</section>

    <h2>Principais Insights</h2>
    <section class="grid">{insight_cards}</section>

    <h2>Comparacao N1 vs N2</h2>
    {html_table(resolution_rows)}

    <h2>Clientes por Tempo Medio de Resolucao</h2>
    <section class="chart">
      {bar_chart(account_rows, "account_name", "avg_resolution_time_minutes")}
    </section>

    <h2>Times por Espera Apos Escalonamento Humano</h2>
    <section class="chart">
      {bar_chart(team_rows, "team_name", "avg_human_wait_until_first_reply_minutes", limit=15)}
    </section>
    {html_table(team_rows, limit=15)}

    <h2>Agentes por Espera Apos Escalonamento Humano</h2>
    {html_table(agent_rows, limit=20)}
  </main>
</body>
</html>
"""


def main() -> None:
    # Este script gera tabelas de relatorio, CSVs e HTML visual para stakeholders.
    if not DB_PATH.exists():
        raise FileNotFoundError(
            "Banco case.duckdb nao encontrado. Rode primeiro: python duck_init.py"
        )

    OUTPUT_DIR.mkdir(exist_ok=True)
    REPORT_DIR.mkdir(exist_ok=True)

    con = duckdb.connect(str(DB_PATH))
    con.execute(REPORT_SQL_PATH.read_text(encoding="utf-8"))

    data = {table_name: fetch_rows(con, table_name) for table_name in REPORT_TABLES}

    for table_name, rows in data.items():
        export_csv(rows, OUTPUT_DIR / f"{table_name}.csv")

    REPORT_PATH.write_text(build_html_report(data), encoding="utf-8")

    print("Relatorio visual criado com sucesso.\n")
    print(f"HTML: {REPORT_PATH}")
    print(f"CSVs: {OUTPUT_DIR}")

    con.close()


if __name__ == "__main__":
    main()

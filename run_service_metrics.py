from pathlib import Path

import duckdb


BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "case.duckdb"
METRICS_SQL_PATH = BASE_DIR / "sql" / "04_service_metrics.sql"


def main() -> None:
    # Este script materializa as metricas finais depois da reconstrucao da jornada.
    if not DB_PATH.exists():
        raise FileNotFoundError(
            "Banco case.duckdb nao encontrado. Rode primeiro: python duck_init.py"
        )

    sql = METRICS_SQL_PATH.read_text(encoding="utf-8")

    con = duckdb.connect(str(DB_PATH))
    con.execute(sql)

    print("Metricas finais criadas com sucesso.\n")

    print("Objetos principais de metricas:")
    con.sql(
        """
        select table_schema, table_name, table_type
        from information_schema.tables
        where table_schema = 'analytics'
          and (
              table_name like 'service_time%'
              or table_name = 'service_metrics_quality_checks'
          )
        order by table_name
        """
    ).show()

    print("\nChecks de qualidade das metricas:")
    con.sql(
        """
        select *
        from analytics.service_metrics_quality_checks
        order by check_name
        """
    ).show()

    print("\nResumo por nivel de resolucao:")
    con.sql(
        """
        select *
        from analytics.service_time_by_resolution_level
        order by resolution_level
        """
    ).show()

    print("\nResumo por cliente:")
    con.sql(
        """
        select
            account_name,
            conversations,
            resolved_conversations,
            round(avg_resolution_time_minutes, 2) as avg_resolution_time_minutes,
            round(avg_queue_minutes, 2) as avg_queue_minutes,
            round(avg_ai_service_minutes, 2) as avg_ai_service_minutes,
            round(avg_human_service_minutes, 2) as avg_human_service_minutes,
            conversations_with_quality_issue
        from analytics.service_time_by_account
        order by account_name
        """
    ).show()

    con.close()


if __name__ == "__main__":
    main()

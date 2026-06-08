from pathlib import Path

import duckdb


BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "case.duckdb"
JOURNEY_SQL_PATH = BASE_DIR / "sql" / "03_journey.sql"


def main() -> None:
    # Este script executa a reconstrucao da jornada depois da camada staging.
    if not DB_PATH.exists():
        raise FileNotFoundError(
            "Banco case.duckdb nao encontrado. Rode primeiro: python duck_init.py"
        )

    sql = JOURNEY_SQL_PATH.read_text(encoding="utf-8")

    con = duckdb.connect(str(DB_PATH))
    con.execute(sql)

    print("Camada de jornada criada com sucesso.\n")

    print("Objetos disponiveis no schema analytics:")
    con.sql(
        """
        select table_schema, table_name, table_type
        from information_schema.tables
        where table_schema = 'analytics'
        order by table_name
        """
    ).show()

    print("\nChecks de qualidade da jornada:")
    con.sql(
        """
        select *
        from analytics.journey_quality_checks
        order by dataset, check_name
        """
    ).show()

    print("\nAmostra do resumo por conversa:")
    con.sql(
        """
        select
            conversation_id,
            account_name,
            inbox_name,
            team_name,
            resolution_level,
            queue_minutes,
            service_minutes,
            ai_service_minutes,
            human_service_minutes,
            minutes_until_first_resolution,
            has_events,
            has_created_event,
            has_resolution_event
        from analytics.conversation_journey_summary
        order by conversation_id
        limit 10
        """
    ).show()

    con.close()


if __name__ == "__main__":
    main()

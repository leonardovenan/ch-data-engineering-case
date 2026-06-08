from pathlib import Path

import duckdb


BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "case.duckdb"
HUMAN_ESCALATION_SQL_PATH = BASE_DIR / "sql" / "05_human_escalation_metrics.sql"


def main() -> None:
    # Este script calcula metricas especificas de escalonamento para humano.
    if not DB_PATH.exists():
        raise FileNotFoundError(
            "Banco case.duckdb nao encontrado. Rode primeiro: python duck_init.py"
        )

    sql = HUMAN_ESCALATION_SQL_PATH.read_text(encoding="utf-8")

    con = duckdb.connect(str(DB_PATH))
    con.execute(sql)

    print("Metricas de escalonamento humano criadas com sucesso.\n")

    print("Objetos de escalonamento humano:")
    con.sql(
        """
        select table_schema, table_name, table_type
        from information_schema.tables
        where table_schema = 'analytics'
          and (
              table_name like 'human_escalation%'
              or table_name = 'first_human_assignment'
          )
        order by table_name
        """
    ).show()

    print("\nChecks de qualidade do escalonamento humano:")
    con.sql(
        """
        select *
        from analytics.human_escalation_quality_checks
        order by check_name
        """
    ).show()

    print("\nResumo por agente humano:")
    con.sql(
        """
        select
            instance,
            agent_user_id,
            agent_name,
            escalated_conversations,
            escalated_conversations_with_human_reply,
            round(avg_human_wait_until_first_reply_minutes, 2)
                as avg_human_wait_until_first_reply_minutes,
            round(median_human_wait_until_first_reply_minutes, 2)
                as median_human_wait_until_first_reply_minutes,
            round(avg_minutes_until_human_assignment, 2)
                as avg_minutes_until_human_assignment,
            conversations_with_quality_issue
        from analytics.human_escalation_by_agent
        order by avg_human_wait_until_first_reply_minutes desc nulls last
        """
    ).show()

    print("\nResumo por time:")
    con.sql(
        """
        select
            account_name,
            team_name,
            escalated_conversations,
            round(avg_human_wait_until_first_reply_minutes, 2)
                as avg_human_wait_until_first_reply_minutes,
            round(avg_minutes_until_human_assignment, 2)
                as avg_minutes_until_human_assignment,
            round(avg_resolution_time_minutes, 2) as avg_resolution_time_minutes
        from analytics.human_escalation_by_team
        order by avg_human_wait_until_first_reply_minutes desc nulls last
        limit 20
        """
    ).show()

    con.close()


if __name__ == "__main__":
    main()

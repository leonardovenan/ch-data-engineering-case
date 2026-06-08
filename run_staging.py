from pathlib import Path

import duckdb


BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "case.duckdb"
STAGING_SQL_PATH = BASE_DIR / "sql" / "02_staging.sql"


def main() -> None:
    # Este script executa a camada de staging depois da ingestao bruta.
    if not DB_PATH.exists():
        raise FileNotFoundError(
            "Banco case.duckdb nao encontrado. Rode primeiro: python duck_init.py"
        )

    sql = STAGING_SQL_PATH.read_text(encoding="utf-8")

    con = duckdb.connect(str(DB_PATH))
    con.execute(sql)

    print("Camada staging criada com sucesso.\n")

    print("Tabelas/views disponiveis no schema staging:")
    con.sql(
        """
        select table_schema, table_name, table_type
        from information_schema.tables
        where table_schema = 'staging'
        order by table_name
        """
    ).show()

    print("\nChecks de qualidade:")
    con.sql(
        """
        select *
        from staging.data_quality_checks
        order by dataset, check_name
        """
    ).show()

    con.close()


if __name__ == "__main__":
    main()

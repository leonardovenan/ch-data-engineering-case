from pathlib import Path
import re

import duckdb


# Paths principais do projeto.
BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = BASE_DIR / "case.duckdb"

# Mapeia extensoes suportadas para a funcao de leitura do DuckDB.
# Parquet nao precisa de reader explicito: o DuckDB le direto pelo caminho.
SUPPORTED_EXTENSIONS = {
    ".csv": "read_csv_auto",
    ".json": "read_json_auto",
    ".jsonl": "read_json_auto",
    ".ndjson": "read_json_auto",
    ".parquet": None,
}


def table_name_from_path(path: Path) -> str:
    # Gera um nome de tabela valido a partir do nome do arquivo.
    name = re.sub(r"[^a-zA-Z0-9_]+", "_", path.stem.lower()).strip("_")
    if not name:
        name = "dataset"
    if name[0].isdigit():
        name = f"t_{name}"
    return name


def unique_table_name(path: Path, used_names: set[str]) -> str:
    # Evita colisao quando dois arquivos geram o mesmo nome de tabela.
    base_name = table_name_from_path(path)
    table_name = base_name
    counter = 2

    while table_name in used_names:
        table_name = f"{base_name}_{counter}"
        counter += 1

    used_names.add(table_name)
    return table_name


def quoted(value: str) -> str:
    # Protege identificadores SQL, como nomes de tabela.
    return '"' + value.replace('"', '""') + '"'


def sql_path(path: Path) -> str:
    # DuckDB aceita barras '/', mesmo no Windows.
    return path.as_posix().replace("'", "''")


def relation_sql(path: Path) -> str:
    # Monta a expressao SQL correta para ler cada tipo de arquivo.
    extension = path.suffix.lower()
    reader = SUPPORTED_EXTENSIONS[extension]
    file_path = sql_path(path)

    if reader is None:
        return f"'{file_path}'"

    return f"{reader}('{file_path}')"


def find_data_files() -> list[Path]:
    # Busca recursivamente arquivos suportados dentro da pasta data.
    if not DATA_DIR.exists():
        return []

    return sorted(
        path
        for path in DATA_DIR.rglob("*")
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )


def load_file(con: duckdb.DuckDBPyConnection, path: Path, table_name: str) -> None:
    # Materializa o arquivo como uma tabela fisica dentro do case.duckdb.
    con.sql(
        f"""
        create or replace table {quoted(table_name)} as
        select *
        from {relation_sql(path)}
        """
    )


def print_table_summary(con: duckdb.DuckDBPyConnection, table_name: str) -> None:
    # Mostra uma checagem rapida para validar se a carga parece correta.
    print(f"\n=== {table_name} ===")
    con.sql(f"select count(*) as rows from {quoted(table_name)}").show()
    con.sql(f"describe {quoted(table_name)}").show()
    con.sql(f"select * from {quoted(table_name)} limit 5").show()


def main() -> None:
    print(f"Database: {DB_PATH}")
    print(f"Data dir: {DATA_DIR}")

    # Sem dados, o script nao falha: ele orienta onde colocar os arquivos.
    data_files = find_data_files()
    if not data_files:
        print("\nNenhum arquivo de dados encontrado.")
        print("Crie a pasta 'data' aqui no projeto e coloque os CSV/JSON/Parquet do case nela.")
        print("Exemplo esperado:")
        print(f"  {DATA_DIR}\\arquivo.csv")
        return

    # Abre ou cria o banco DuckDB local.
    con = duckdb.connect(str(DB_PATH))
    used_names: set[str] = set()

    # Cada arquivo vira uma tabela com nome derivado do proprio arquivo.
    for path in data_files:
        table_name = unique_table_name(path, used_names)
        print(f"\nCarregando {path.relative_to(BASE_DIR)} -> tabela {table_name}")
        load_file(con, path, table_name)
        print_table_summary(con, table_name)

    print("\nTabelas criadas no DuckDB:")
    con.sql("show tables").show()
    con.close()


if __name__ == "__main__":
    main()

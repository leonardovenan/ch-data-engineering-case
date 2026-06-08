from pathlib import Path
import subprocess
import sys


BASE_DIR = Path(__file__).resolve().parent

PIPELINE_STEPS = [
    ("Ingestao bruta", "duck_init.py"),
    ("Staging", "run_staging.py"),
    ("Jornada", "run_journey.py"),
    ("Metricas de servico", "run_service_metrics.py"),
    ("Escalonamento humano", "run_human_escalation_metrics.py"),
    ("Relatorio stakeholder", "run_stakeholder_report.py"),
]


def main() -> None:
    # Executa a pipeline inteira usando o mesmo Python do ambiente atual.
    for step_name, script_name in PIPELINE_STEPS:
        print(f"\n=== {step_name} ===")
        subprocess.run(
            [sys.executable, str(BASE_DIR / script_name)],
            cwd=BASE_DIR,
            check=True,
        )

    print("\nPipeline concluida com sucesso.")
    print(f"Relatorio: {BASE_DIR / 'reports' / 'service_metrics_report.html'}")
    print(f"CSVs: {BASE_DIR / 'outputs'}")


if __name__ == "__main__":
    main()

# Cloud Humans Data Engineering Case

Pipeline local em DuckDB para calcular metricas de tempo de servico a partir dos CSVs crus do case da Cloud Humans.

O projeto ingere os dados, limpa duplicatas/imperfeicoes, reconstrui a jornada das conversas, calcula metricas de resolucao/fila/atendimento/IA/humano/escalonamento e gera um relatorio HTML para stakeholders.

## Quickstart

Crie e ative o ambiente virtual:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Garanta que os quatro CSVs estejam em `data/`:

```text
data/accounts.csv
data/agents.csv
data/conversations.csv
data/conversation_events.csv
```

Execute a pipeline inteira:

```powershell
python run_all.py
```

Ou execute passo a passo:

```powershell
python duck_init.py
python run_staging.py
python run_journey.py
python run_service_metrics.py
python run_human_escalation_metrics.py
python run_stakeholder_report.py
```

Saidas principais:

```text
case.duckdb
reports/service_metrics_report.html
outputs/report_kpis.csv
outputs/report_resolution_level.csv
outputs/report_account_ranking.csv
outputs/report_human_wait_by_team.csv
outputs/report_human_wait_by_agent.csv
outputs/report_key_insights.csv
```

## O Que Foi Construido

O fluxo segue uma estrutura em camadas:

```text
CSVs crus
  -> tabelas raw no DuckDB
  -> staging limpo e tipado
  -> jornada granular de eventos
  -> metricas finais por conversa
  -> agregacoes e relatorio visual
```

Arquivos principais:

```text
sql/02_staging.sql
sql/03_journey.sql
sql/04_service_metrics.sql
sql/05_human_escalation_metrics.sql
sql/06_stakeholder_report.sql
duck_init.py
run_staging.py
run_journey.py
run_service_metrics.py
run_human_escalation_metrics.py
run_stakeholder_report.py
run_all.py
```

## Principais Metricas

Tabela final por conversa:

```text
analytics.service_time_metrics
```

Metricas implementadas:

- `resolution_time_minutes`: tempo entre criacao e ultima resolucao conhecida.
- `first_resolution_time_minutes`: tempo entre criacao e primeira resolucao.
- `queue_minutes`: tempo sem agente atribuido.
- `service_minutes`: tempo total com agente atribuido.
- `ai_service_minutes`: tempo em atendimento por IA.
- `human_service_minutes`: tempo em atendimento humano.
- `first_reply_time_minutes`: tempo ate primeira resposta.
- `first_human_reply_time_minutes`: tempo ate primeira resposta humana desde a criacao.
- `human_wait_until_first_reply_minutes`: tempo entre primeira atribuicao humana e primeira resposta humana.

Agregacoes:

```text
analytics.service_time_by_account
analytics.service_time_by_inbox
analytics.service_time_by_team
analytics.service_time_by_resolution_level
analytics.human_escalation_by_agent
analytics.human_escalation_by_team
```

## Principais Achados

Com os dados processados, o relatorio gerado aponta:

- 5.000 conversas apos deduplicacao.
- 4.743 conversas resolvidas.
- 587 conversas reabertas.
- Tempo medio de resolucao: 1.587,94 minutos.
- Tempo medio de fila: 14,77 minutos.
- Tempo medio de atendimento IA: 22,20 minutos.
- Tempo medio de atendimento humano: 434,84 minutos.
- N2 exige muito mais atendimento humano que N1: 678,01 min vs 255,99 min em media.
- Pacific Goods tem o maior tempo medio de resolucao: 1.813,58 minutos.
- Pacific Goods / Suporte tem a maior espera media apos escalonamento humano: 23,49 minutos.

## Decisoes Tecnicas

- Usei DuckDB por ser simples, rapido para CSVs locais e excelente para SQL analitico sem infraestrutura externa.
- Mantive SQL em arquivos separados por camada para deixar a logica auditavel.
- Removi duplicatas exatas na staging com `select distinct`.
- Validei duplicidade por chaves compostas, como `instance + account_id + conversation_id` e `instance + account_id + event_id`.
- Usei `staging.stg_conversations.created_at_utc` como fallback quando o evento `conversation_created` esta ausente.
- Usei a ultima resolucao como `resolution_time_minutes`, porque ela representa o ciclo completo em conversas reabertas.
- Mantive a primeira resolucao como metrica separada para analises operacionais.
- Classifiquei intervalos de jornada como `queue`, `ai_service`, `human_service`, `resolved` e `terminal`.
- Calculei espera apos escalonamento humano como `first_human_reply_created_at_utc - first_human_assigned_at_utc`.

## Qualidade Dos Dados

Imperfeicoes identificadas e tratadas:

- 40 duplicatas exatas em `conversations`.
- 120 duplicatas exatas em `conversation_events`.
- 394 conversas sem evento `conversation_created`, resolvidas com fallback de `conversations.created_at`.
- 15 conversas sem eventos granulares.
- 257 conversas sem evento de resolucao.
- 335 conversas escaladas para humano sem `first_human_reply_created_at`.

Esses casos ficam expostos em views de qualidade:

```text
staging.data_quality_checks
analytics.journey_quality_checks
analytics.service_metrics_quality_checks
analytics.human_escalation_quality_checks
```

## Arquitetura Em Producao

Para resolver as tres dores citadas no case, eu implementaria uma arquitetura com camadas bem definidas.

### Performance

- Manteria os dados crus em S3 em camada bronze, preferencialmente em Parquet particionado por data de evento.
- Usaria uma camada silver com dados limpos, tipados e deduplicados.
- Criaria marts gold materializados para BI, como `service_time_metrics`, `service_time_by_team` e `human_escalation_by_agent`.
- O dashboard consultaria somente tabelas gold, nunca tabelas transacionais ou staging.
- No Redshift, usaria sort keys/distribution keys em campos como `account_id`, `conversation_id`, `created_at` e `event_at`.
- Agregacoes pesadas seriam precomputadas por jobs incrementais.

### Visibilidade

- Criaria um catalogo de metricas com definicao, formula, granularidade e owner.
- Exporia KPIs por cliente, time, inbox, agente, N1/N2 e IA vs humano.
- Manteria checks de qualidade publicados em uma tabela de monitoramento.
- Alertas seriam disparados para quedas bruscas de volume, aumento de eventos sem match ou crescimento de metricas nulas.

### Regras De Negocio

- As regras ficariam versionadas em SQL/dbt, nao embutidas diretamente no BI.
- Cada metrica teria uma definicao unica e testada.
- Conversas reabertas teriam duas metricas oficiais: primeira resolucao e resolucao final.
- Tempo de fila seria sempre periodo sem agente atribuido.
- Tempo de atendimento seria sempre periodo com agente atribuido, separado entre IA e humano.
- Tempo apos escalonamento humano seria contado a partir da primeira atribuicao humana ate a primeira resposta humana.

### Orquestracao E Operacao

- Airflow, Dagster ou Prefect para orquestrar cargas.
- dbt para transformacoes, testes e documentacao de modelos.
- Redshift como camada analitica final, mantendo S3 como data lake.
- Jobs incrementais por data de evento para evitar recomputar todo o historico.
- Logs e metricas de execucao enviados para CloudWatch ou ferramenta equivalente.
- Alertas para falha de pipeline, SLA quebrado ou checks de qualidade criticos.

## Limitacoes

- O projeto usa DuckDB local para demonstracao; em producao a mesma modelagem deveria ser executada em Redshift/dbt ou stack equivalente.
- Alguns eventos de criacao e resolucao estao ausentes; foram tratados com fallback e flags de qualidade.
- A primeira resposta humana vem do campo consolidado de `conversations`, nao de eventos de mensagem granular.
- Nomes de agentes podem repetir entre instancias; por isso relatorios por agente usam `instance + user_id`.
- O relatorio HTML e simples e estatico; em producao eu entregaria em BI com filtros interativos.

## Estrutura Dos Passos

### Passo 1: ingestao bruta

`duck_init.py` le arquivos em `data/` e cria tabelas raw no `case.duckdb`:

```text
accounts
agents
conversations
conversation_events
```

### Passo 2: staging

`sql/02_staging.sql` cria:

```text
staging.stg_accounts
staging.stg_agents
staging.stg_conversations
staging.stg_conversation_events
staging.data_quality_checks
```

### Passo 3: jornada

`sql/03_journey.sql` cria:

```text
analytics.dim_agents_by_user
analytics.conversation_event_timeline
analytics.conversation_journey_intervals
analytics.conversation_journey_event_summary
analytics.conversation_journey_summary
analytics.journey_quality_checks
```

### Passo 4: metricas de servico

`sql/04_service_metrics.sql` cria:

```text
analytics.service_time_metrics
analytics.service_time_by_account
analytics.service_time_by_inbox
analytics.service_time_by_team
analytics.service_time_by_resolution_level
analytics.service_metrics_quality_checks
```

### Passo 5: escalonamento humano

`sql/05_human_escalation_metrics.sql` cria:

```text
analytics.first_human_assignment
analytics.human_escalation_metrics
analytics.human_escalation_by_agent
analytics.human_escalation_by_team
analytics.human_escalation_quality_checks
```

### Passo 6: relatorio visual

`sql/06_stakeholder_report.sql` e `run_stakeholder_report.py` geram o HTML e os CSVs finais em `reports/` e `outputs/`.

## Conclusao Final Para O Case

O principal problema da arquitetura atual nao é apenas a lentidao do dashboard. A lentidao e um sintoma de uma arquitetura em que o BI consulta o Redshift diretamente sobre dados pouco modelados, aplicando regras de negocio, joins, deduplicacoes e calculos pesados no momento da visualizacao.

Na pratica, o dashboard esta acumulando responsabilidades demais:

- consultar dados operacionais/brutos
- reconstruir a jornada das conversas
- aplicar regras de fila, atendimento, IA e humano
- calcular metricas de tempo
- agregar resultados por cliente, time, inbox e agente
- apresentar os graficos para o usuario final

Isso explica as tres queixas do case:

1. **Lentidao/performance**: cada interacao no dashboard pode disparar queries caras, com joins, janelas temporais e agregacoes.
2. **Falta de visibilidade**: as entidades analiticas que o cliente precisa enxergar nao existem prontas, como jornada da conversa, tempo em fila, tempo humano e tempo apos escalonamento.
3. **Regras de negocio mal definidas**: se cada grafico implementa sua propria query, a mesma metrica pode ter definicoes diferentes em dashboards distintos.

A solucao proposta e introduzir uma camada de transformacao entre o dado bruto e o BI:

```text
MongoDB/Postgres
  -> S3 raw/bronze
  -> Redshift raw
  -> camada de transformacao versionada e testada
  -> Redshift marts/gold
  -> BI
```

O trabalho desenvolvido neste projeto simula essa arquitetura localmente com DuckDB:

```text
raw tables
  -> staging.stg_*
  -> analytics.conversation_journey_intervals
  -> analytics.service_time_metrics
  -> analytics.human_escalation_metrics
  -> analytics.report_*
```

Em producao, essa mesma modelagem poderia ser implementada com dbt rodando sobre Redshift, orquestrada por Airflow, Dagster ou ferramenta equivalente. Para volumes maiores, a camada intermediaria poderia usar Spark/Glue antes de publicar tabelas analiticas no warehouse.

O ponto central e: **o dashboard nao deveria calcular a metrica; ele deveria consumir a metrica**.

Por isso, a camada final deveria expor tabelas materializadas como:

```text
gold.service_time_metrics
gold.service_time_by_account
gold.service_time_by_inbox
gold.service_time_by_team
gold.service_time_by_agent
gold.human_escalation_metrics
```

Com isso:

- dashboards ficam mais rapidos, porque passam a consultar tabelas prontas para consumo
- clientes ganham visibilidade sobre indicadores criticos da operacao
- regras de negocio ficam centralizadas, versionadas, testadas e documentadas
- metricas deixam de depender de queries soltas no BI
- suporte recebe menos chamados sobre divergencia de numeros

Portanto, a entrega recomendada para a Cloud Humans nao e apenas um conjunto de graficos novos, mas uma mudanca de desenho: criar uma camada analitica confiavel entre os dados operacionais e a experiencia do cliente no BI.

-- Step 6: tabelas de apoio para relatorio visual.
-- Este arquivo assume que as metricas dos passos 4 e 5 ja foram criadas.

create schema if not exists analytics;

-- KPIs gerais para abrir o relatorio.
create or replace table analytics.report_kpis as
select
    count(*) as conversations,
    count(*) filter (where is_resolved) as resolved_conversations,
    count(*) filter (where was_reopened) as reopened_conversations,
    round(avg(resolution_time_minutes) filter (where resolution_time_minutes is not null), 2)
        as avg_resolution_time_minutes,
    round(avg(queue_minutes), 2) as avg_queue_minutes,
    round(avg(service_minutes), 2) as avg_service_minutes,
    round(avg(ai_service_minutes), 2) as avg_ai_service_minutes,
    round(avg(human_service_minutes), 2) as avg_human_service_minutes,
    round(avg(first_reply_time_minutes) filter (where first_reply_time_minutes is not null), 2)
        as avg_first_reply_time_minutes,
    count(*) filter (where has_data_quality_issue) as conversations_with_quality_issue
from analytics.service_time_metrics;

-- Comparacao direta entre N1 e N2.
create or replace table analytics.report_resolution_level as
select
    resolution_level,
    conversations,
    resolved_conversations,
    reopened_conversations,
    round(avg_resolution_time_minutes, 2) as avg_resolution_time_minutes,
    round(median_resolution_time_minutes, 2) as median_resolution_time_minutes,
    round(avg_queue_minutes, 2) as avg_queue_minutes,
    round(avg_ai_service_minutes, 2) as avg_ai_service_minutes,
    round(avg_human_service_minutes, 2) as avg_human_service_minutes,
    round(avg_first_reply_time_minutes, 2) as avg_first_reply_time_minutes,
    round(avg_first_human_reply_time_minutes, 2) as avg_first_human_reply_time_minutes
from analytics.service_time_by_resolution_level
order by resolution_level;

-- Ranking por cliente.
create or replace table analytics.report_account_ranking as
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
order by avg_resolution_time_minutes desc nulls last;

-- Times com maior espera ate a primeira resposta humana apos escalonamento.
create or replace table analytics.report_human_wait_by_team as
select
    account_name,
    team_name,
    escalated_conversations,
    round(avg_human_wait_until_first_reply_minutes, 2)
        as avg_human_wait_until_first_reply_minutes,
    round(median_human_wait_until_first_reply_minutes, 2)
        as median_human_wait_until_first_reply_minutes,
    round(avg_minutes_until_human_assignment, 2) as avg_minutes_until_human_assignment,
    round(avg_resolution_time_minutes, 2) as avg_resolution_time_minutes
from analytics.human_escalation_by_team
order by avg_human_wait_until_first_reply_minutes desc nulls last;

-- Agentes humanos com maior espera media ate a primeira resposta.
create or replace table analytics.report_human_wait_by_agent as
select
    instance,
    first_human_assignee_id as agent_user_id,
    first_human_assignee_name as agent_name,
    count(*) as escalated_conversations,
    count(*) filter (where has_first_human_reply) as escalated_conversations_with_human_reply,
    round(
        avg(human_wait_until_first_reply_minutes) filter (
            where human_wait_until_first_reply_minutes is not null
        ),
        2
    )
        as avg_human_wait_until_first_reply_minutes,
    round(
        median(human_wait_until_first_reply_minutes) filter (
            where human_wait_until_first_reply_minutes is not null
        ),
        2
    )
        as median_human_wait_until_first_reply_minutes,
    round(avg(minutes_until_human_assignment), 2) as avg_minutes_until_human_assignment,
    count(*) filter (where has_data_quality_issue) as conversations_with_quality_issue
from analytics.human_escalation_metrics
group by
    instance,
    first_human_assignee_id,
    first_human_assignee_name
order by avg_human_wait_until_first_reply_minutes desc nulls last;

-- Mensagens/insights principais em formato de tabela para o HTML.
create or replace table analytics.report_key_insights as
with
resolution_gap as (
    select
        max(case when resolution_level = 'n1' then avg_human_service_minutes end) as n1_human_minutes,
        max(case when resolution_level = 'n2' then avg_human_service_minutes end) as n2_human_minutes
    from analytics.report_resolution_level
),
slowest_account as (
    select account_name, avg_resolution_time_minutes
    from analytics.report_account_ranking
    order by avg_resolution_time_minutes desc nulls last
    limit 1
),
slowest_team as (
    select account_name, team_name, avg_human_wait_until_first_reply_minutes
    from analytics.report_human_wait_by_team
    order by avg_human_wait_until_first_reply_minutes desc nulls last
    limit 1
)
select
    1 as insight_order,
    'N2 exige muito mais atendimento humano que N1' as insight_title,
    'N2 tem media de ' || round(n2_human_minutes, 2)
        || ' min de atendimento humano vs '
        || round(n1_human_minutes, 2) || ' min em N1.' as insight_text
from resolution_gap

union all

select
    2,
    'Cliente com maior tempo medio de resolucao',
    account_name || ' aparece com media de '
        || avg_resolution_time_minutes || ' min.'
from slowest_account

union all

select
    3,
    'Maior espera apos escalonamento humano',
    account_name || ' / ' || team_name || ' tem media de '
        || avg_human_wait_until_first_reply_minutes
        || ' min ate primeira resposta humana.'
from slowest_team;

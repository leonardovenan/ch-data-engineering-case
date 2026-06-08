-- Step 4: metricas finais de tempo de servico.
-- Este arquivo assume que o run_journey.py ja criou analytics.conversation_journey_summary.

create schema if not exists analytics;

-- Uma linha por conversa com metricas finais prontas para consumo analitico.
create or replace table analytics.service_time_metrics as
select
    instance,
    account_id,
    account_name,
    timezone,
    inbox_id,
    inbox_name,
    team_name,
    conversation_id,
    display_id,
    current_status,
    resolution_level,
    created_at_utc,
    first_resolved_at_utc,
    last_resolved_at_utc,
    first_reply_created_at_utc,
    first_human_reply_created_at_utc,
    has_events,
    has_created_event,
    has_resolution_event,
    current_status = 'resolved' or has_resolution_event as is_resolved,
    reopened_count > 0 as was_reopened,
    reopened_count,
    resolved_event_count,

    -- Tempo de resolucao final: criacao ate a ultima resolucao conhecida.
    minutes_until_last_resolution as resolution_time_minutes,

    -- Tempo ate a primeira resolucao: util para ver quando a conversa foi resolvida pela primeira vez.
    minutes_until_first_resolution as first_resolution_time_minutes,

    -- Tempos calculados pela jornada de eventos.
    queue_minutes,
    service_minutes,
    ai_service_minutes,
    human_service_minutes,
    unknown_service_minutes,

    -- Tempos calculados a partir dos campos consolidados de conversas.
    minutes_until_first_reply as first_reply_time_minutes,
    minutes_until_first_human_reply as first_human_reply_time_minutes,

    -- Flags para analise e filtros no dashboard.
    not has_events
        or not has_created_event
        or (current_status = 'resolved' and not has_resolution_event)
        or unknown_service_minutes > 0
        as has_data_quality_issue
from analytics.conversation_journey_summary;

-- Agregacao por cliente.
create or replace table analytics.service_time_by_account as
select
    account_id,
    account_name,
    count(*) as conversations,
    count(*) filter (where is_resolved) as resolved_conversations,
    count(*) filter (where was_reopened) as reopened_conversations,
    avg(resolution_time_minutes) filter (where resolution_time_minutes is not null) as avg_resolution_time_minutes,
    median(resolution_time_minutes) filter (where resolution_time_minutes is not null) as median_resolution_time_minutes,
    avg(queue_minutes) as avg_queue_minutes,
    avg(service_minutes) as avg_service_minutes,
    avg(ai_service_minutes) as avg_ai_service_minutes,
    avg(human_service_minutes) as avg_human_service_minutes,
    avg(first_reply_time_minutes) filter (where first_reply_time_minutes is not null) as avg_first_reply_time_minutes,
    avg(first_human_reply_time_minutes) filter (
        where first_human_reply_time_minutes is not null
    ) as avg_first_human_reply_time_minutes,
    count(*) filter (where has_data_quality_issue) as conversations_with_quality_issue
from analytics.service_time_metrics
group by
    account_id,
    account_name;

-- Agregacao por inbox/canal.
create or replace table analytics.service_time_by_inbox as
select
    account_id,
    account_name,
    inbox_id,
    inbox_name,
    count(*) as conversations,
    count(*) filter (where is_resolved) as resolved_conversations,
    avg(resolution_time_minutes) filter (where resolution_time_minutes is not null) as avg_resolution_time_minutes,
    avg(queue_minutes) as avg_queue_minutes,
    avg(service_minutes) as avg_service_minutes,
    avg(ai_service_minutes) as avg_ai_service_minutes,
    avg(human_service_minutes) as avg_human_service_minutes,
    avg(first_reply_time_minutes) filter (where first_reply_time_minutes is not null) as avg_first_reply_time_minutes,
    count(*) filter (where has_data_quality_issue) as conversations_with_quality_issue
from analytics.service_time_metrics
group by
    account_id,
    account_name,
    inbox_id,
    inbox_name;

-- Agregacao por time.
create or replace table analytics.service_time_by_team as
select
    account_id,
    account_name,
    team_name,
    count(*) as conversations,
    count(*) filter (where is_resolved) as resolved_conversations,
    avg(resolution_time_minutes) filter (where resolution_time_minutes is not null) as avg_resolution_time_minutes,
    avg(queue_minutes) as avg_queue_minutes,
    avg(service_minutes) as avg_service_minutes,
    avg(ai_service_minutes) as avg_ai_service_minutes,
    avg(human_service_minutes) as avg_human_service_minutes,
    avg(first_reply_time_minutes) filter (where first_reply_time_minutes is not null) as avg_first_reply_time_minutes,
    count(*) filter (where has_data_quality_issue) as conversations_with_quality_issue
from analytics.service_time_metrics
group by
    account_id,
    account_name,
    team_name;

-- Agregacao por nivel de resolucao para comparar N1 e N2.
create or replace table analytics.service_time_by_resolution_level as
select
    resolution_level,
    count(*) as conversations,
    count(*) filter (where is_resolved) as resolved_conversations,
    count(*) filter (where was_reopened) as reopened_conversations,
    avg(resolution_time_minutes) filter (where resolution_time_minutes is not null) as avg_resolution_time_minutes,
    median(resolution_time_minutes) filter (where resolution_time_minutes is not null) as median_resolution_time_minutes,
    avg(queue_minutes) as avg_queue_minutes,
    avg(service_minutes) as avg_service_minutes,
    avg(ai_service_minutes) as avg_ai_service_minutes,
    avg(human_service_minutes) as avg_human_service_minutes,
    avg(first_reply_time_minutes) filter (where first_reply_time_minutes is not null) as avg_first_reply_time_minutes,
    avg(first_human_reply_time_minutes) filter (
        where first_human_reply_time_minutes is not null
    ) as avg_first_human_reply_time_minutes,
    count(*) filter (where has_data_quality_issue) as conversations_with_quality_issue
from analytics.service_time_metrics
group by
    resolution_level;

-- Checks da camada final.
create or replace view analytics.service_metrics_quality_checks as
select
    'service_time_metrics' as dataset,
    'rows' as check_name,
    count(*) as check_value
from analytics.service_time_metrics

union all

select
    'service_time_metrics',
    'resolved_without_resolution_time',
    count(*) filter (where is_resolved and resolution_time_minutes is null)
from analytics.service_time_metrics

union all

select
    'service_time_metrics',
    'negative_resolution_time',
    count(*) filter (where resolution_time_minutes < 0)
from analytics.service_time_metrics

union all

select
    'service_time_metrics',
    'negative_first_reply_time',
    count(*) filter (where first_reply_time_minutes < 0)
from analytics.service_time_metrics

union all

select
    'service_time_metrics',
    'conversations_with_quality_issue',
    count(*) filter (where has_data_quality_issue)
from analytics.service_time_metrics;

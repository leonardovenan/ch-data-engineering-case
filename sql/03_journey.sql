-- Step 3: reconstrucao da jornada de cada conversa.
-- Este arquivo assume que o run_staging.py ja criou as tabelas staging.stg_*.

create schema if not exists analytics;

-- Dimensao auxiliar de agentes por instancia e user_id.
-- A fonte agents pode ter account_id vazio; por isso a chave mais estavel aqui e instance + user_id.
create or replace table analytics.dim_agents_by_user as
select
    instance,
    user_id,
    any_value(agent_name) as agent_name,
    any_value(agent_role) as agent_role,
    bool_or(is_ai_agent) as is_ai_agent
from staging.stg_agents
group by
    instance,
    user_id;

-- Eventos ordenados com o proximo evento da mesma conversa.
-- O lead cria o fim de cada intervalo de estado da conversa.
create or replace table analytics.conversation_event_timeline as
select
    e.event_id,
    e.instance,
    e.account_id,
    e.inbox_id,
    e.conversation_id,
    e.event_type,
    e.user_id,
    e.created_at_utc as event_at_utc,
    row_number() over (
        partition by e.instance, e.account_id, e.conversation_id
        order by e.created_at_utc, e.event_id
    ) as event_sequence,
    lead(e.created_at_utc) over (
        partition by e.instance, e.account_id, e.conversation_id
        order by e.created_at_utc, e.event_id
    ) as next_event_at_utc,
    lead(e.event_type) over (
        partition by e.instance, e.account_id, e.conversation_id
        order by e.created_at_utc, e.event_id
    ) as next_event_type
from staging.stg_conversation_events e;

-- Intervalos de jornada.
-- Cada linha representa o estado da conversa entre um evento e o proximo.
create or replace table analytics.conversation_journey_intervals as
select
    t.instance,
    t.account_id,
    c.account_name,
    c.timezone,
    t.inbox_id,
    conv.inbox_name,
    conv.team_name,
    t.conversation_id,
    conv.display_id,
    conv.status as current_status,
    conv.resolution_level,
    t.event_id,
    t.event_sequence,
    t.event_type,
    t.event_at_utc as interval_start_at_utc,
    t.next_event_at_utc as interval_end_at_utc,
    datediff('second', t.event_at_utc, t.next_event_at_utc) / 60.0 as interval_minutes,
    t.user_id as assigned_user_id,
    a.agent_name as assigned_agent_name,
    a.agent_role as assigned_agent_role,
    a.is_ai_agent,
    case
        when t.next_event_at_utc is null then 'terminal'
        when t.event_type = 'conversation_resolved' then 'resolved'
        when t.user_id is null then 'queue'
        when coalesce(a.is_ai_agent, false) then 'ai_service'
        when a.user_id is not null then 'human_service'
        else 'unknown_assignee_service'
    end as interval_state
from analytics.conversation_event_timeline t
left join staging.stg_conversations conv
    on t.instance = conv.instance
    and t.account_id = conv.account_id
    and t.conversation_id = conv.conversation_id
left join staging.stg_accounts c
    on t.instance = c.instance
    and t.account_id = c.account_id
left join analytics.dim_agents_by_user a
    on t.instance = a.instance
    and t.user_id = a.user_id;

-- Agregado dos intervalos por conversa.
-- Fica separado para permitir que o resumo final parta da tabela de conversas original.
create or replace table analytics.conversation_journey_event_summary as
select
    i.instance,
    i.account_id,
    i.inbox_id,
    i.conversation_id,
    min(case when i.event_type = 'conversation_created' then i.interval_start_at_utc end) as created_at_utc,
    min(case when i.event_type = 'conversation_resolved' then i.interval_start_at_utc end) as first_resolved_at_utc,
    max(case when i.event_type = 'conversation_resolved' then i.interval_start_at_utc end) as last_resolved_at_utc,
    count(*) filter (where i.event_type = 'conversation_opened') as reopened_count,
    count(*) filter (where i.event_type = 'conversation_resolved') as resolved_event_count,
    sum(coalesce(i.interval_minutes, 0)) filter (
        where i.interval_state in ('queue', 'ai_service', 'human_service', 'unknown_assignee_service')
    ) as active_journey_minutes,
    sum(coalesce(i.interval_minutes, 0)) filter (where i.interval_state = 'queue') as queue_minutes,
    sum(coalesce(i.interval_minutes, 0)) filter (
        where i.interval_state in ('ai_service', 'human_service', 'unknown_assignee_service')
    ) as service_minutes,
    sum(coalesce(i.interval_minutes, 0)) filter (where i.interval_state = 'ai_service') as ai_service_minutes,
    sum(coalesce(i.interval_minutes, 0)) filter (where i.interval_state = 'human_service') as human_service_minutes,
    sum(coalesce(i.interval_minutes, 0)) filter (where i.interval_state = 'unknown_assignee_service') as unknown_service_minutes,
    datediff(
        'second',
        min(case when i.event_type = 'conversation_created' then i.interval_start_at_utc end),
        min(case when i.event_type = 'conversation_resolved' then i.interval_start_at_utc end)
    ) / 60.0 as minutes_until_first_resolution,
    datediff(
        'second',
        min(case when i.event_type = 'conversation_created' then i.interval_start_at_utc end),
        max(case when i.event_type = 'conversation_resolved' then i.interval_start_at_utc end)
    ) / 60.0 as minutes_until_last_resolution
from analytics.conversation_journey_intervals i
group by
    i.instance,
    i.account_id,
    i.inbox_id,
    i.conversation_id;

-- Resumo por conversa.
-- Esta tabela parte de staging.stg_conversations para garantir uma linha por conversa do CSV original.
create or replace table analytics.conversation_journey_summary as
select
    c.instance,
    c.account_id,
    a.account_name,
    a.timezone,
    c.inbox_id,
    c.inbox_name,
    c.team_name,
    c.conversation_id,
    c.display_id,
    c.status as current_status,
    c.resolution_level,
    c.created_at_utc as conversation_created_at_utc,
    e.created_at_utc as event_created_at_utc,
    coalesce(e.created_at_utc, c.created_at_utc) as created_at_utc,
    e.first_resolved_at_utc,
    e.last_resolved_at_utc,
    coalesce(e.reopened_count, 0) as reopened_count,
    coalesce(e.resolved_event_count, 0) as resolved_event_count,
    coalesce(e.active_journey_minutes, 0) as active_journey_minutes,
    coalesce(e.queue_minutes, 0) as queue_minutes,
    coalesce(e.service_minutes, 0) as service_minutes,
    coalesce(e.ai_service_minutes, 0) as ai_service_minutes,
    coalesce(e.human_service_minutes, 0) as human_service_minutes,
    coalesce(e.unknown_service_minutes, 0) as unknown_service_minutes,
    datediff(
        'second',
        coalesce(e.created_at_utc, c.created_at_utc),
        e.first_resolved_at_utc
    ) / 60.0 as minutes_until_first_resolution,
    datediff(
        'second',
        coalesce(e.created_at_utc, c.created_at_utc),
        e.last_resolved_at_utc
    ) / 60.0 as minutes_until_last_resolution,
    c.first_reply_created_at_utc,
    c.first_human_reply_created_at_utc,
    datediff('second', c.created_at_utc, c.first_reply_created_at_utc) / 60.0 as minutes_until_first_reply,
    datediff('second', c.created_at_utc, c.first_human_reply_created_at_utc) / 60.0 as minutes_until_first_human_reply,
    e.conversation_id is not null as has_events,
    e.created_at_utc is not null as has_created_event,
    e.first_resolved_at_utc is not null as has_resolution_event
from staging.stg_conversations c
left join staging.stg_accounts a
    on c.instance = a.instance
    and c.account_id = a.account_id
left join analytics.conversation_journey_event_summary e
    on c.instance = e.instance
    and c.account_id = e.account_id
    and c.inbox_id = e.inbox_id
    and c.conversation_id = e.conversation_id;

-- Checks especificos da reconstrucao de jornada.
create or replace view analytics.journey_quality_checks as
select
    'conversation_event_timeline' as dataset,
    'rows' as check_name,
    count(*) as check_value
from analytics.conversation_event_timeline

union all

select
    'conversation_journey_intervals',
    'negative_intervals',
    count(*) filter (where interval_minutes < 0)
from analytics.conversation_journey_intervals

union all

select
    'conversation_journey_intervals',
    'terminal_intervals',
    count(*) filter (where interval_state = 'terminal')
from analytics.conversation_journey_intervals

union all

select
    'conversation_journey_intervals',
    'unknown_assignee_service_intervals',
    count(*) filter (where interval_state = 'unknown_assignee_service')
from analytics.conversation_journey_intervals

union all

select
    'conversation_journey_summary',
    'rows',
    count(*)
from analytics.conversation_journey_summary

union all

select
    'conversation_journey_summary',
    'conversations_without_events',
    count(*) filter (where not has_events)
from analytics.conversation_journey_summary

union all

select
    'conversation_journey_summary',
    'conversations_without_created_event',
    count(*) filter (where not has_created_event)
from analytics.conversation_journey_summary

union all

select
    'conversation_journey_summary',
    'conversations_without_resolution_event',
    count(*) filter (where not has_resolution_event)
from analytics.conversation_journey_summary

union all

select
    'conversation_journey_summary',
    'conversations_without_created_at_fallback',
    count(*) filter (where created_at_utc is null)
from analytics.conversation_journey_summary;

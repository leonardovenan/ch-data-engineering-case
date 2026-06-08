-- Step 5: metricas de escalonamento humano.
-- Este arquivo assume que run_journey.py e run_service_metrics.py ja foram executados.

create schema if not exists analytics;

-- Primeira atribuicao humana por conversa.
-- Consideramos escalonamento humano quando um evento passa a ter user_id de agente nao IA.
create or replace table analytics.first_human_assignment as
select
    instance,
    account_id,
    inbox_id,
    conversation_id,
    assigned_user_id as first_human_assignee_id,
    assigned_agent_name as first_human_assignee_name,
    interval_start_at_utc as first_human_assigned_at_utc
from (
    select
        i.*,
        row_number() over (
            partition by i.instance, i.account_id, i.conversation_id
            order by i.interval_start_at_utc, i.event_id
        ) as human_assignment_sequence
    from analytics.conversation_journey_intervals i
    where i.interval_state = 'human_service'
)
where human_assignment_sequence = 1;

-- Uma linha por conversa escalada para humano.
-- A principal metrica aqui e o tempo entre atribuicao humana e primeira resposta humana.
create or replace table analytics.human_escalation_metrics as
select
    m.instance,
    m.account_id,
    m.account_name,
    m.timezone,
    m.inbox_id,
    m.inbox_name,
    m.team_name,
    m.conversation_id,
    m.display_id,
    m.current_status,
    m.resolution_level,
    m.created_at_utc,
    h.first_human_assignee_id,
    h.first_human_assignee_name,
    h.first_human_assigned_at_utc,
    m.first_human_reply_created_at_utc,
    datediff(
        'second',
        h.first_human_assigned_at_utc,
        m.first_human_reply_created_at_utc
    ) / 60.0 as human_wait_until_first_reply_minutes,
    datediff('second', m.created_at_utc, h.first_human_assigned_at_utc) / 60.0 as minutes_until_human_assignment,
    m.resolution_time_minutes,
    m.queue_minutes,
    m.human_service_minutes,
    m.ai_service_minutes,
    m.was_reopened,
    m.has_data_quality_issue,
    m.first_human_reply_created_at_utc is not null as has_first_human_reply,
    datediff(
        'second',
        h.first_human_assigned_at_utc,
        m.first_human_reply_created_at_utc
    ) < 0 as has_human_reply_before_assignment
from analytics.service_time_metrics m
inner join analytics.first_human_assignment h
    on m.instance = h.instance
    and m.account_id = h.account_id
    and m.inbox_id = h.inbox_id
    and m.conversation_id = h.conversation_id;

-- Desempenho por agente humano.
-- Esta agregacao responde quem tem melhores/piores tempos apos escalonamento.
create or replace table analytics.human_escalation_by_agent as
select
    instance,
    first_human_assignee_id as agent_user_id,
    first_human_assignee_name as agent_name,
    count(*) as escalated_conversations,
    count(*) filter (where has_first_human_reply) as escalated_conversations_with_human_reply,
    avg(human_wait_until_first_reply_minutes) filter (
        where human_wait_until_first_reply_minutes is not null
    ) as avg_human_wait_until_first_reply_minutes,
    median(human_wait_until_first_reply_minutes) filter (
        where human_wait_until_first_reply_minutes is not null
    ) as median_human_wait_until_first_reply_minutes,
    avg(minutes_until_human_assignment) as avg_minutes_until_human_assignment,
    avg(human_service_minutes) as avg_human_service_minutes,
    avg(resolution_time_minutes) filter (where resolution_time_minutes is not null) as avg_resolution_time_minutes,
    count(*) filter (where has_human_reply_before_assignment) as conversations_with_reply_before_assignment,
    count(*) filter (where has_data_quality_issue) as conversations_with_quality_issue
from analytics.human_escalation_metrics
group by
    instance,
    first_human_assignee_id,
    first_human_assignee_name;

-- Desempenho de escalonamento por time.
create or replace table analytics.human_escalation_by_team as
select
    account_id,
    account_name,
    team_name,
    count(*) as escalated_conversations,
    count(*) filter (where has_first_human_reply) as escalated_conversations_with_human_reply,
    avg(human_wait_until_first_reply_minutes) filter (
        where human_wait_until_first_reply_minutes is not null
    ) as avg_human_wait_until_first_reply_minutes,
    median(human_wait_until_first_reply_minutes) filter (
        where human_wait_until_first_reply_minutes is not null
    ) as median_human_wait_until_first_reply_minutes,
    avg(minutes_until_human_assignment) as avg_minutes_until_human_assignment,
    avg(human_service_minutes) as avg_human_service_minutes,
    avg(resolution_time_minutes) filter (where resolution_time_minutes is not null) as avg_resolution_time_minutes,
    count(*) filter (where has_data_quality_issue) as conversations_with_quality_issue
from analytics.human_escalation_metrics
group by
    account_id,
    account_name,
    team_name;

-- Checks especificos da metrica de escalonamento.
create or replace view analytics.human_escalation_quality_checks as
select
    'human_escalation_metrics' as dataset,
    'rows' as check_name,
    count(*) as check_value
from analytics.human_escalation_metrics

union all

select
    'human_escalation_metrics',
    'missing_first_human_reply',
    count(*) filter (where not has_first_human_reply)
from analytics.human_escalation_metrics

union all

select
    'human_escalation_metrics',
    'negative_human_wait_until_first_reply',
    count(*) filter (where human_wait_until_first_reply_minutes < 0)
from analytics.human_escalation_metrics

union all

select
    'human_escalation_metrics',
    'reply_before_assignment',
    count(*) filter (where has_human_reply_before_assignment)
from analytics.human_escalation_metrics

union all

select
    'human_escalation_metrics',
    'conversations_with_quality_issue',
    count(*) filter (where has_data_quality_issue)
from analytics.human_escalation_metrics;

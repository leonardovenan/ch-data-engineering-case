-- Step 2: limpeza e padronizacao dos dados brutos.
-- Este arquivo assume que o duck_init.py ja criou as tabelas raw:
-- accounts, agents, conversations e conversation_events.

create schema if not exists staging;

-- Contas/clientes.
-- Mantemos a granularidade original: uma linha por conta e instancia.
create or replace table staging.stg_accounts as
select distinct
    cast(instance as integer) as instance,
    cast(account_id as integer) as account_id,
    trim(account_name) as account_name,
    trim(timezone) as timezone,
    cast(business_open_hour as integer) as business_open_hour,
    cast(business_close_hour as integer) as business_close_hour
from accounts;

-- Agentes.
-- account_id vem vazio em parte dos dados; por isso usamos try_cast para nao quebrar a carga.
create or replace table staging.stg_agents as
select distinct
    cast(id as integer) as agent_record_id,
    try_cast(account_id as integer) as account_id,
    cast(instance as integer) as instance,
    cast(user_id as integer) as user_id,
    trim(agent_name) as agent_name,
    lower(trim(agent_role)) as agent_role,
    try_cast(created_at as timestamp) as created_at_utc,
    try_cast(updated_at as timestamp) as updated_at_utc,
    try_cast(active_at as timestamp) as active_at_utc,
    cast(auto_offline as boolean) as auto_offline,
    cast(is_ai_agent as boolean) as is_ai_agent
from agents;

-- Conversas.
-- Timestamps recebem sufixo _utc porque o enunciado informa que todos estao em UTC.
create or replace table staging.stg_conversations as
select distinct
    cast(id as integer) as conversation_id,
    cast(instance as integer) as instance,
    cast(account_id as integer) as account_id,
    cast(inbox_id as integer) as inbox_id,
    trim(inbox_name) as inbox_name,
    trim(team_name) as team_name,
    try_cast(assignee_id as integer) as current_assignee_id,
    cast(display_id as integer) as display_id,
    cast(contact_id as integer) as contact_id,
    cast(contact_inbox_id as integer) as contact_inbox_id,
    lower(trim(status)) as status,
    nullif(trim(cached_label_list), '') as cached_label_list,
    lower(nullif(trim(resolution_level), '')) as resolution_level,
    trim(uuid) as conversation_uuid,
    try_cast(created_at as timestamp) as created_at_utc,
    try_cast(updated_at as timestamp) as updated_at_utc,
    try_cast(contact_last_seen_at as timestamp) as contact_last_seen_at_utc,
    try_cast(agent_last_seen_at as timestamp) as agent_last_seen_at_utc,
    try_cast(assignee_last_seen_at as timestamp) as assignee_last_seen_at_utc,
    try_cast(first_reply_created_at as timestamp) as first_reply_created_at_utc,
    try_cast(first_human_reply_created_at as timestamp) as first_human_reply_created_at_utc
from conversations;

-- Eventos granulares.
-- user_id nulo representa conversa sem responsavel em eventos de mudanca de atribuicao.
create or replace table staging.stg_conversation_events as
select distinct
    cast(id as integer) as event_id,
    lower(trim(event_type)) as event_type,
    cast(account_id as integer) as account_id,
    cast(inbox_id as integer) as inbox_id,
    try_cast(user_id as integer) as user_id,
    cast(conversation_id as integer) as conversation_id,
    try_cast(created_at as timestamp) as created_at_utc,
    try_cast(updated_at as timestamp) as updated_at_utc,
    cast(instance as integer) as instance
from conversation_events;

-- Checks de qualidade em formato tabular.
-- A ideia aqui e documentar problemas potenciais antes da modelagem das metricas.
create or replace view staging.data_quality_checks as
select
    'accounts' as dataset,
    'rows' as check_name,
    count(*) as check_value
from staging.stg_accounts

union all

select
    'agents',
    'rows',
    count(*)
from staging.stg_agents

union all

select
    'conversations',
    'rows',
    count(*)
from staging.stg_conversations

union all

select
    'conversation_events',
    'rows',
    count(*)
from staging.stg_conversation_events

union all

select
    'conversations',
    'duplicate_conversation_key',
    (select count(*) from staging.stg_conversations)
        - (
            select count(*)
            from (
                select distinct instance, account_id, conversation_id
                from staging.stg_conversations
            )
        )

union all

select
    'conversation_events',
    'duplicate_event_key',
    (select count(*) from staging.stg_conversation_events)
        - (
            select count(*)
            from (
                select distinct instance, account_id, event_id
                from staging.stg_conversation_events
            )
        )

union all

select
    'conversations',
    'raw_exact_duplicates_removed',
    (select count(*) from conversations)
        - (select count(*) from staging.stg_conversations)

union all

select
    'conversation_events',
    'raw_exact_duplicates_removed',
    (select count(*) from conversation_events)
        - (select count(*) from staging.stg_conversation_events)

union all

select
    'conversations',
    'missing_created_at',
    count(*) filter (where created_at_utc is null)
from staging.stg_conversations

union all

select
    'conversation_events',
    'missing_created_at',
    count(*) filter (where created_at_utc is null)
from staging.stg_conversation_events

union all

select
    'conversation_events',
    'events_without_matching_conversation',
    count(*)
from staging.stg_conversation_events e
left join staging.stg_conversations c
    on e.instance = c.instance
    and e.account_id = c.account_id
    and e.conversation_id = c.conversation_id
where c.conversation_id is null

union all

select
    'conversation_events',
    'unknown_event_type',
    count(*) filter (
        where event_type not in (
            'conversation_created',
            'conversation_assignment_changed',
            'conversation_resolved',
            'conversation_opened'
        )
    )
from staging.stg_conversation_events;

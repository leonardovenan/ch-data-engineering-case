select
    conversation_id,
    account_name,
    inbox_name,
    team_name,
    resolution_level,
    created_at_utc,
    first_resolved_at_utc,
    last_resolved_at_utc,
    first_resolution_time_minutes,
    resolution_time_minutes
from analytics.service_time_metrics
where conversation_id = 100002;
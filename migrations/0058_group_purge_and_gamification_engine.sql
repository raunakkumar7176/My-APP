-- ============================================================
-- 0058 — Study Group Realtime Upgrades & Global Student Gamification System
-- ============================================================

begin;

-- ============================================================
-- 1. 1-Week Auto-Purge for Group Messages
-- ============================================================

create or replace function public.rpc_purge_old_group_messages()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted_count integer;
begin
  delete from public.group_messages
  where created_at < now() - interval '7 days';
  
  get diagnostics v_deleted_count = row_count;
  return v_deleted_count;
end;
$$;

grant execute on function public.rpc_purge_old_group_messages() to authenticated, service_role;

-- Setup pg_cron job if pg_cron is enabled
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Remove existing job if present
    begin
      perform cron.unschedule('purge_old_group_messages_weekly');
    exception when others then null;
    end;

    perform cron.schedule(
      'purge_old_group_messages_weekly',
      '0 2 * * *', -- Daily at 2 AM UTC
      'select public.rpc_purge_old_group_messages()'
    );
  end if;
end $$;

-- ============================================================
-- 2. System Events & Message Type in Group Messages
-- ============================================================

alter table public.group_messages
add column if not exists message_type text not null default 'text';

alter table public.group_messages
drop constraint if exists group_messages_message_type_check;

alter table public.group_messages
add constraint group_messages_message_type_check
check (message_type in ('text', 'system_event'));

-- Helper RPC to broadcast a system event in group chat
create or replace function public.rpc_send_group_system_event(
  p_group_id uuid,
  p_event_text text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  -- Ensure caller is member of group
  if not exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = auth.uid()
  ) then
    raise exception 'You are not a member of this group.';
  end if;

  insert into public.group_messages (
    group_id,
    sender_id,
    body,
    message_type,
    created_at
  ) values (
    p_group_id,
    null, -- system messages have null sender_id
    p_event_text,
    'system_event',
    now()
  ) returning id into v_message_id;

  return v_message_id;
end;
$$;

grant execute on function public.rpc_send_group_system_event(uuid, text) to authenticated;

-- ============================================================
-- 3. Student Gamification & Points Engine
-- ============================================================

alter table public.profiles
add column if not exists total_points integer not null default 0,
add column if not exists weekly_points integer not null default 0,
add column if not exists last_points_reset_at timestamptz not null default now();

create index if not exists idx_profiles_total_points on public.profiles (total_points desc);
create index if not exists idx_profiles_weekly_points on public.profiles (weekly_points desc);

-- Atomic Study Points Crediting RPC
create or replace function public.rpc_award_study_points(
  p_user_id uuid,
  p_points integer,
  p_activity_type text default 'activity'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_total integer;
  v_reset_needed boolean := false;
begin
  -- Caller verification: users award points for their own completed activities
  if auth.uid() is null or auth.uid() <> p_user_id then
    p_user_id := auth.uid();
  end if;

  if p_user_id is null or p_points <= 0 then
    return 0;
  end if;

  -- Check if weekly points need reset (Sunday midnight UTC rollover)
  select (last_points_reset_at < date_trunc('week', now() at time zone 'UTC'))
  into v_reset_needed
  from public.profiles
  where id = p_user_id;

  if v_reset_needed then
    update public.profiles
    set weekly_points = 0,
        last_points_reset_at = now()
    where id = p_user_id;
  end if;

  -- Increment points atomically
  update public.profiles
  set total_points = coalesce(total_points, 0) + p_points,
      weekly_points = coalesce(weekly_points, 0) + p_points
  where id = p_user_id
  returning total_points into v_new_total;

  return coalesce(v_new_total, 0);
end;
$$;

grant execute on function public.rpc_award_study_points(uuid, integer, text) to authenticated;

-- Weekly leaderboard reset RPC (can be called via cron every Sunday midnight UTC)
create or replace function public.rpc_reset_weekly_leaderboard()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set weekly_points = 0,
      last_points_reset_at = now();
end;
$$;

grant execute on function public.rpc_reset_weekly_leaderboard() to service_role;

-- ============================================================
-- 4. Weekly Cohort Leaderboard RPC
-- ============================================================

create or replace function public.rpc_get_weekly_cohort_leaderboard(
  p_group_id uuid default null,
  p_limit integer default 50
)
returns table (
  user_id uuid,
  full_name text,
  student_code text,
  avatar_url text,
  total_points integer,
  weekly_points integer,
  rank bigint
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if p_group_id is not null then
    return query
    select
      p.id as user_id,
      p.full_name,
      p.student_code,
      p.avatar_url,
      coalesce(p.total_points, 0) as total_points,
      coalesce(p.weekly_points, 0) as weekly_points,
      dense_rank() over (
        order by coalesce(p.weekly_points, 0) desc, coalesce(p.total_points, 0) desc, p.created_at asc
      ) as rank
    from public.profiles p
    inner join public.group_members gm on gm.user_id = p.id
    where gm.group_id = p_group_id
    order by weekly_points desc, total_points desc
    limit p_limit;
  else
    return query
    select
      p.id as user_id,
      p.full_name,
      p.student_code,
      p.avatar_url,
      coalesce(p.total_points, 0) as total_points,
      coalesce(p.weekly_points, 0) as weekly_points,
      dense_rank() over (
        order by coalesce(p.weekly_points, 0) desc, coalesce(p.total_points, 0) desc, p.created_at asc
      ) as rank
    from public.profiles p
    where p.student_code is not null
    order by weekly_points desc, total_points desc
    limit p_limit;
  end if;
end;
$$;

grant execute on function public.rpc_get_weekly_cohort_leaderboard(uuid, integer) to authenticated;

-- ============================================================
-- 5. Global Student Search by Unique ID RPC
-- ============================================================

create or replace function public.rpc_search_student_by_code(p_student_code text)
returns table (
  id uuid,
  full_name text,
  student_code text,
  total_points integer,
  weekly_points integer,
  bio text,
  avatar_url text,
  exam_targets jsonb
)
language sql
security definer
set search_path = public
stable
as $$
  select
    p.id,
    p.full_name,
    p.student_code,
    coalesce(p.total_points, 0) as total_points,
    coalesce(p.weekly_points, 0) as weekly_points,
    p.bio,
    p.avatar_url,
    to_jsonb(coalesce(p.exam_targets, '{}'::text[])) as exam_targets
  from public.profiles p
  where upper(trim(p.student_code)) = upper(trim(p_student_code))
  limit 1;
$$;

grant execute on function public.rpc_search_student_by_code(text) to authenticated;

commit;

notify pgrst, 'reload schema';

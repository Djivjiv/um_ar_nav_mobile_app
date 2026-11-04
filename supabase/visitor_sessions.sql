-- ============================================================================
-- UM-AR Nav — server-controlled visitor sessions
--
-- Sessions are started and timed by the server, so a visitor can't lengthen
-- one from the device. Also adds the is_visitor flag to the evaluation tables.
--
-- Safe to run more than once. NOT run automatically — paste it into the
-- Supabase SQL editor. Run it AFTER:
--   1. admin app db/user_roles.sql        (public.is_admin())
--   2. supabase/navigation_evaluation.sql (navigation_sessions, sus_responses)
--
-- The app needs this file: until it is run, "Continue as Visitor" shows an
-- error while online, because start_visitor_session doesn't exist.
--
-- Who can do what:
--   visitors  start a session only through start_visitor_session(), read their
--             own session by device_code, and never insert, update or delete.
--   admins    read every session.
--
-- device_code is the install's random UUID (see the header of
-- navigation_evaluation.sql). It is the shared id across visitor_sessions,
-- navigation_sessions, sus_responses and feedback_comments.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Table
-- ---------------------------------------------------------------------------
create table if not exists public.visitor_sessions (
  id           uuid primary key default gen_random_uuid(),
  device_code  text,
  started_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  is_expired   boolean not null default false
);

-- The table already exists if the app has created visitors before.
alter table public.visitor_sessions
  add column if not exists device_code text;

-- device_id is the old per-install id. It is kept (nullable) only because the
-- admin app's Visitor screen reads it; new rows copy device_code into it.
alter table public.visitor_sessions
  add column if not exists device_id text;
alter table public.visitor_sessions
  alter column device_id drop not null;

create index if not exists visitor_sessions_device_code_idx
  on public.visitor_sessions (device_code, expires_at desc);

-- ---------------------------------------------------------------------------
-- 2. Functions — all times here are the server's
-- ---------------------------------------------------------------------------
create or replace function public.visitor_session_row(s public.visitor_sessions)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id',          s.id,
    'device_code', s.device_code,
    'started_at',  s.started_at,
    'expires_at',  s.expires_at,
    'is_expired',  s.is_expired or s.expires_at <= now(),
    'server_now',  now()
  );
$$;

-- Starts a 2-hour session for this device, or returns the one still running,
-- so calling it again can never lengthen a session. Only the device_code comes
-- from the caller; every time is set here.
create or replace function public.start_visitor_session(p_device_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  code text := lower(trim(p_device_code));
  s public.visitor_sessions;
begin
  if code is null or code !~
     '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'Invalid device code.' using errcode = '22023';
  end if;

  -- Two taps at the same moment still make one session.
  perform pg_advisory_xact_lock(hashtext('visitor_session:' || code));

  update public.visitor_sessions
     set is_expired = true
   where device_code = code
     and not is_expired
     and expires_at <= now();

  select * into s
    from public.visitor_sessions
   where device_code = code
     and not is_expired
   order by expires_at desc
   limit 1;

  if not found then
    insert into public.visitor_sessions
      (device_code, device_id, started_at, expires_at, is_expired)
    values
      (code, code, now(), now() + interval '2 hours', false)
    returning * into s;
  end if;

  return public.visitor_session_row(s);
end;
$$;

-- This device's session with the server's current time, or null when it
-- doesn't exist or belongs to another device. Setting is_expired on the row
-- ends a session early: the app sees it within about a minute.
create or replace function public.visitor_session_status(
  p_session_id uuid,
  p_device_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.visitor_sessions;
begin
  update public.visitor_sessions
     set is_expired = true
   where id = p_session_id
     and device_code = lower(trim(p_device_code))
     and not is_expired
     and expires_at <= now();

  select * into s
    from public.visitor_sessions
   where id = p_session_id
     and device_code = lower(trim(p_device_code));

  if not found then
    return null;
  end if;
  return public.visitor_session_row(s);
end;
$$;

revoke all on function public.visitor_session_row(public.visitor_sessions) from public;
revoke all on function public.start_visitor_session(text) from public;
revoke all on function public.visitor_session_status(uuid, text) from public;
grant execute on function public.start_visitor_session(text) to anon, authenticated;
grant execute on function public.visitor_session_status(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Row-level security
-- ---------------------------------------------------------------------------
-- Visitors have no login, so a policy can only know their device_code if the
-- request states it, in an x-device-code header. The app itself reads through
-- visitor_session_status(), which also returns the server's time; this policy
-- covers any direct read. device_code is a random UUID, so it can't be guessed.
alter table public.visitor_sessions enable row level security;

-- Policies are OR-ed, so any older one could leave the table open or allow
-- writes. Every policy on this table is dropped and replaced by the two below.
do $$
declare
  p record;
begin
  for p in select policyname from pg_policies
           where schemaname = 'public' and tablename = 'visitor_sessions'
  loop
    execute format('drop policy %I on public.visitor_sessions', p.policyname);
  end loop;
end $$;

create policy "visitor reads own session"
  on public.visitor_sessions for select
  to anon, authenticated
  using (
    device_code = lower(
      nullif(current_setting('request.headers', true), '')::json
        ->> 'x-device-code'
    )
  );

create policy "admin read visitor_sessions"
  on public.visitor_sessions for select
  to authenticated
  using (public.is_admin());

-- No insert, update or delete for the app: the functions above run as their
-- owner, so they don't need these.
revoke all on public.visitor_sessions from anon, authenticated;
grant select on public.visitor_sessions to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. The visitor flag on evaluation rows
-- ---------------------------------------------------------------------------
-- Generated by the database, so it can't disagree with the row, and it also
-- covers rows already logged: a row with no signed-in user is a visitor's. The
-- app doesn't send this column. Every visitor row also carries device_code.
alter table if exists public.navigation_sessions
  add column if not exists is_visitor boolean
    generated always as (user_id is null) stored;

alter table if exists public.sus_responses
  add column if not exists is_visitor boolean
    generated always as (user_id is null) stored;

-- Make the new functions and columns visible to PostgREST immediately.
notify pgrst, 'reload schema';

-- ============================================================================
-- UM-AR Nav — one SUS response per person
--
-- A person is user_id when signed in, else device_code. The admin app counts
-- people the same way (core/utils/sus_dedupe.dart).
--
-- NOT run automatically. Run it AFTER supabase/navigation_evaluation.sql, in
-- the Supabase SQL editor, ONE SECTION AT A TIME: select a section's text and
-- run only that. The editor runs a whole paste as one transaction, so a
-- failure in section 2 would also undo section 1.
--
-- Until section 1 has run, the phone only knows what it stored itself: a
-- person who reinstalls the app can be asked again.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- SECTION 1. The server check. Safe to run more than once.
-- ---------------------------------------------------------------------------
-- The app may only insert into sus_responses, never read it, so it asks this
-- function instead. It answers yes or no and returns no row data. A signed-in
-- person is taken from their login, so nobody can ask about another user_id.
create or replace function public.has_submitted_sus(p_device_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is not null then exists (
      select 1 from public.sus_responses where user_id = auth.uid()
    )
    else exists (
      select 1 from public.sus_responses
       where user_id is null
         and device_code = lower(trim(p_device_code))
    )
  end;
$$;

revoke all on function public.has_submitted_sus(text) from public;
grant execute on function public.has_submitted_sus(text) to anon, authenticated;

notify pgrst, 'reload schema';


-- ---------------------------------------------------------------------------
-- SECTION 2. The unique rule.
-- ---------------------------------------------------------------------------
-- WARNING: this WILL FAIL with "could not create unique index" if duplicates
-- already exist. Nothing is changed when it fails. Look at them first:
--
--   select 'user' as kind, user_id::text as person, count(*)
--     from public.sus_responses
--    where user_id is not null
--    group by user_id having count(*) > 1
--   union all
--   select 'device', device_code, count(*)
--     from public.sus_responses
--    where user_id is null and device_code is not null
--    group by device_code having count(*) > 1;
--
-- This file does not delete anything. Those rows are evaluation data, so which
-- to keep is your decision. The admin app counts each person's earliest
-- response, and this lists the later ones it already ignores:
--
--   select id, user_id, device_code, submitted_at
--     from (
--       select *, row_number() over (
--                   partition by coalesce(user_id::text, device_code)
--                   order by submitted_at nulls last, id) as nth
--         from public.sus_responses
--        where user_id is not null or device_code is not null
--     ) ranked
--    where nth > 1;
--
-- The device rule covers only rows with no user_id. Two people signed in on a
-- shared phone each answer once, and answering as a visitor doesn't use up a
-- person's signed-in answer. Rows with neither id can't be matched to anyone
-- and aren't limited.
--
-- A second insert is refused with error 23505. The app's write queue reads
-- that as "the server already has it" and removes the row from the phone.
create unique index if not exists sus_responses_one_per_user
  on public.sus_responses (user_id)
  where user_id is not null;

create unique index if not exists sus_responses_one_per_device
  on public.sus_responses (device_code)
  where user_id is null and device_code is not null;

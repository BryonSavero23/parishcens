-- ============================================================
-- PARISH CENSUS FORM — Supabase (PostgreSQL) Schema
-- ------------------------------------------------------------
-- Run this whole script inside the Supabase SQL Editor.
-- It creates 3 tables (households, household_members, pastoral_care),
-- plus an aggregated view for the admin dashboard, plus permissive
-- RLS policies suitable for a public-submission form.
--
-- SECURITY NOTE:
--   * Anonymous users can INSERT (submit the census).
--   * Anonymous users canNOT SELECT/UPDATE/DELETE.
--   * Reading is granted to `authenticated` role — so the admin
--     dashboard must be viewed while logged in via Supabase Auth
--     (magic-link / email + password). See admin.html for the
--     login flow. Change the SELECT policy if you want a shared
--     service_role key instead.
-- ============================================================

-- Extensions ------------------------------------------------------
create extension if not exists "pgcrypto";

-- Enum: sacrament boolean-ish (kept as booleans below; enum for future use)
do $$
begin
  if not exists (select 1 from pg_type where typname = 'yes_no_unknown') then
    create type yes_no_unknown as enum ('yes','no','unknown');
  end if;
end$$;

-- ============================================================
-- 1) HOUSEHOLD INFORMATION  (top-level submission)
-- ============================================================
create table if not exists public.households (
    id                uuid primary key default gen_random_uuid(),
    submitted_at      timestamptz not null default now(),

    -- Header
    name              text        not null,   -- respondent / family name
    bec               text,                   -- Basic Ecclesial Community

    -- §1 Household Information
    address           text        not null,
    head_of_household text        not null,
    phone_whatsapp    text,
    email             text
);

comment on table public.households is 'One row per submitted Parish Census form.';
comment on column public.households.bec is 'Basic Ecclesial Community identifier.';

create index if not exists households_submitted_at_idx
    on public.households (submitted_at desc);
create index if not exists households_name_idx
    on public.households (name);

-- ============================================================
-- 2) MEMBER DETAILS
--    Split into two logical groups (I) marriage row and
--    (II) children rows — but stored in one unified table
--    using a `member_type` discriminator so the list is dynamic.
-- ============================================================
create table if not exists public.household_members (
    id              uuid primary key default gen_random_uuid(),
    household_id    uuid not null references public.households(id) on delete cascade,
    created_at      timestamptz not null default now(),

    -- 'couple'  → §2.I Marriage Date and Place (typically 1 row per household)
    -- 'child'   → §2.II Children (0..n rows per household)
    member_type     text not null check (member_type in ('couple','child')),

    -- Common
    display_order   int  not null default 0,        -- preserves the order the user typed
    full_name       text not null,                  -- Name / Name of Couple

    -- Marriage-only fields (nullable for children)
    marriage_date   date,
    marriage_place  text,

    -- Child-only fields (nullable for couple row)
    date_of_birth       date,
    sacrament_baptism      boolean not null default false,
    sacrament_holy_comm    boolean not null default false,
    sacrament_confirmation boolean not null default false,
    sacrament_married      boolean not null default false
);

comment on table public.household_members is
    'Dynamic list of members per household. member_type = couple | child.';

create index if not exists household_members_household_id_idx
    on public.household_members (household_id);
create index if not exists household_members_type_idx
    on public.household_members (household_id, member_type, display_order);

-- ============================================================
-- 3) PASTORAL CARE & SERVICE  (1-to-1 with household)
-- ============================================================
create table if not exists public.pastoral_care (
    id                    uuid primary key default gen_random_uuid(),
    household_id          uuid not null unique
                          references public.households(id) on delete cascade,
    created_at            timestamptz not null default now(),

    homebound_sick        boolean not null default false,
    request_visit         boolean not null default false,   -- valid only when homebound_sick = true
    new_to_parish         boolean not null default false,
    talents_skills        text                              -- free-text gifts / skills
);

comment on table public.pastoral_care is
    'Pastoral care answers — one row per household submission.';

create index if not exists pastoral_care_household_id_idx
    on public.pastoral_care (household_id);

-- ============================================================
-- 4) CONVENIENCE VIEW for the admin dashboard
--    Aggregates a household + its member counts + pastoral answers
--    into a single row that can be sorted and searched easily.
-- ============================================================
create or replace view public.census_admin_view as
select
    h.id,
    h.submitted_at,
    h.name,
    h.bec,
    h.address,
    h.head_of_household,
    h.phone_whatsapp,
    h.email,
    coalesce((select count(*) from public.household_members m
              where m.household_id = h.id and m.member_type = 'couple'), 0) as couple_rows,
    coalesce((select count(*) from public.household_members m
              where m.household_id = h.id and m.member_type = 'child'), 0)  as children_count,
    pc.homebound_sick,
    pc.request_visit,
    pc.new_to_parish,
    pc.talents_skills
from public.households h
left join public.pastoral_care pc on pc.household_id = h.id;

-- ============================================================
-- 5) ROW-LEVEL SECURITY
-- ============================================================
alter table public.households        enable row level security;
alter table public.household_members enable row level security;
alter table public.pastoral_care     enable row level security;

-- Allow anonymous inserts (public form submissions) --------------
-- We first grant the table-level INSERT privilege to the Supabase
-- `anon` and `authenticated` roles (RLS by itself is not enough —
-- the role still needs the underlying GRANT), then attach a permissive
-- RLS policy scoped to `public`, which covers anon + authenticated +
-- any future role Supabase adds.
grant usage on schema public to anon, authenticated;
grant insert on public.households        to anon, authenticated;
grant insert on public.household_members to anon, authenticated;
grant insert on public.pastoral_care     to anon, authenticated;

drop policy if exists "anon can insert households"        on public.households;
drop policy if exists "anon can insert household_members" on public.household_members;
drop policy if exists "anon can insert pastoral_care"     on public.pastoral_care;

-- `to public` explicitly includes the anon role, so unauthenticated
-- visitors submitting the census form pass the WITH CHECK clause.
create policy "anon can insert households"
    on public.households for insert
    to public
    with check (true);

create policy "anon can insert household_members"
    on public.household_members for insert
    to public
    with check (true);

create policy "anon can insert pastoral_care"
    on public.pastoral_care for insert
    to public
    with check (true);

-- Allow SELECT only to authenticated (admin) users ---------------
drop policy if exists "authed can read households"        on public.households;
drop policy if exists "authed can read household_members" on public.household_members;
drop policy if exists "authed can read pastoral_care"     on public.pastoral_care;

create policy "authed can read households"
    on public.households for select
    to authenticated
    using (true);

create policy "authed can read household_members"
    on public.household_members for select
    to authenticated
    using (true);

create policy "authed can read pastoral_care"
    on public.pastoral_care for select
    to authenticated
    using (true);

-- The view inherits RLS from underlying tables, so authenticated
-- users automatically get read access to census_admin_view.

-- ============================================================
-- Done. Verify with:
--   select * from public.census_admin_view order by submitted_at desc;
-- ============================================================

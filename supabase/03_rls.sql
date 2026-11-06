-- ==============================================================================
-- EVENTORA — ROW LEVEL SECURITY (RLS) POLICIES
-- File: supabase/03_rls.sql
-- Description: Tenant isolation, role-based security, student data protection.
-- ==============================================================================

-- Enable Row Level Security on all application tables
alter table public.colleges enable row level security;
alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.registrations enable row level security;

-- ------------------------------------------------------------------------------
-- HELPER FUNCTIONS (Avoids recursive policy lookups on profiles)
-- ------------------------------------------------------------------------------
create or replace function public.auth_user_role()
returns text as $$
    select role from public.profiles where id = auth.uid();
$$ language sql stable security definer;

create or replace function public.auth_user_college_id()
returns uuid as $$
    select college_id from public.profiles where id = auth.uid();
$$ language sql stable security definer;

-- ------------------------------------------------------------------------------
-- 1. COLLEGES POLICIES
-- ------------------------------------------------------------------------------
-- Anyone (authenticated or anonymous) can view colleges for discovery and signup
drop policy if exists "colleges_select_public" on public.colleges;
create policy "colleges_select_public"
    on public.colleges for select
    using (true);

-- Only superadmins can create, edit, or delete colleges
drop policy if exists "colleges_superadmin_manage" on public.colleges;
create policy "colleges_superadmin_manage"
    on public.colleges for all
    using (public.auth_user_role() = 'superadmin')
    with check (public.auth_user_role() = 'superadmin');

-- ------------------------------------------------------------------------------
-- 2. PROFILES POLICIES
-- ------------------------------------------------------------------------------
-- Users can view their own profile
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
    on public.profiles for select
    using (id = auth.uid());

-- College admins can view student profiles belonging to their college
drop policy if exists "profiles_select_college_admin" on public.profiles;
create policy "profiles_select_college_admin"
    on public.profiles for select
    using (
        public.auth_user_role() = 'admin'
        and college_id = public.auth_user_college_id()
    );

-- Superadmins can view all profiles
drop policy if exists "profiles_select_superadmin" on public.profiles;
create policy "profiles_select_superadmin"
    on public.profiles for select
    using (public.auth_user_role() = 'superadmin');

-- Users can update basic profile info, but CANNOT self-escalate role or alter college_id
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
    on public.profiles for update
    using (id = auth.uid())
    with check (
        id = auth.uid()
        and role = (select role from public.profiles where id = auth.uid())
        and college_id is not distinct from (select college_id from public.profiles where id = auth.uid())
    );

-- Superadmins can update any profile (including managing roles)
drop policy if exists "profiles_update_superadmin" on public.profiles;
create policy "profiles_update_superadmin"
    on public.profiles for update
    using (public.auth_user_role() = 'superadmin');

-- ------------------------------------------------------------------------------
-- 3. EVENTS POLICIES
-- ------------------------------------------------------------------------------
-- Anyone (guests and students) can view published events
drop policy if exists "events_select_published" on public.events;
create policy "events_select_published"
    on public.events for select
    using (published = true);

-- College Admins can view ALL events from their own college (published and drafts)
drop policy if exists "events_select_college_admin" on public.events;
create policy "events_select_college_admin"
    on public.events for select
    using (
        public.auth_user_role() = 'admin'
        and college_id = public.auth_user_college_id()
    );

-- Superadmin can view all events
drop policy if exists "events_select_superadmin" on public.events;
create policy "events_select_superadmin"
    on public.events for select
    using (public.auth_user_role() = 'superadmin');

-- College Admins can INSERT events only for their assigned college
drop policy if exists "events_insert_college_admin" on public.events;
create policy "events_insert_college_admin"
    on public.events for insert
    with check (
        public.auth_user_role() = 'admin'
        and college_id = public.auth_user_college_id()
        and created_by = auth.uid()
    );

-- College Admins can UPDATE/DELETE events only belonging to their assigned college
drop policy if exists "events_modify_college_admin" on public.events;
create policy "events_modify_college_admin"
    on public.events for update
    using (
        public.auth_user_role() = 'admin'
        and college_id = public.auth_user_college_id()
    )
    with check (
        college_id = public.auth_user_college_id()
    );

drop policy if exists "events_delete_college_admin" on public.events;
create policy "events_delete_college_admin"
    on public.events for delete
    using (
        public.auth_user_role() = 'admin'
        and college_id = public.auth_user_college_id()
    );

-- ------------------------------------------------------------------------------
-- 4. REGISTRATIONS POLICIES
-- ------------------------------------------------------------------------------
-- Students can view their own registrations
drop policy if exists "registrations_select_student" on public.registrations;
create policy "registrations_select_student"
    on public.registrations for select
    using (student_id = auth.uid());

-- College Admins can view registrations for events hosted by their college
drop policy if exists "registrations_select_college_admin" on public.registrations;
create policy "registrations_select_college_admin"
    on public.registrations for select
    using (
        public.auth_user_role() = 'admin'
        and event_id in (
            select id from public.events where college_id = public.auth_user_college_id()
        )
    );

-- Superadmin can view all registrations
drop policy if exists "registrations_select_superadmin" on public.registrations;
create policy "registrations_select_superadmin"
    on public.registrations for select
    using (public.auth_user_role() = 'superadmin');

-- Students can cancel their own registrations
drop policy if exists "registrations_cancel_student" on public.registrations;
create policy "registrations_cancel_student"
    on public.registrations for update
    using (student_id = auth.uid())
    with check (
        student_id = auth.uid()
        and status in ('cancelled', 'registered')
    );


-- ==============================================================================
-- EVENTORA — COMPLETE CONSOLIDATED SETUP SCRIPT
-- File: supabase/00_full_setup.sql
-- Description: Run this SINGLE script in your Supabase SQL Editor to initialize 
--              the entire database (Tables, Indexes, Triggers, Functions, RLS, Seed).
-- ==============================================================================

begin;

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 1. COLLEGES TABLE
-- ------------------------------------------------------------------------------
create table if not exists public.colleges (
    id uuid primary key default uuid_generate_v4(),
    identifier varchar(50) unique not null,
    name varchar(255) not null,
    location varchar(255),
    website varchar(255),
    logo_url text,
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null
);

create index if not exists idx_colleges_identifier on public.colleges(identifier);

-- ------------------------------------------------------------------------------
-- 2. USER PROFILES TABLE
-- ------------------------------------------------------------------------------
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email varchar(255) unique not null,
    full_name varchar(255) not null,
    role varchar(50) not null default 'student' check (role in ('student', 'admin', 'superadmin')),
    college_id uuid references public.colleges(id) on delete set null,
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null
);

create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_profiles_college on public.profiles(college_id);

-- ------------------------------------------------------------------------------
-- 3. EVENTS TABLE
-- ------------------------------------------------------------------------------
create table if not exists public.events (
    id uuid primary key default uuid_generate_v4(),
    college_id uuid not null references public.colleges(id) on delete cascade,
    created_by uuid references public.profiles(id) on delete cascade,
    title varchar(255) not null,
    description text not null,
    category varchar(100) not null default 'General',
    venue varchar(255) not null,
    banner_url text,
    start_at timestamptz not null,
    end_at timestamptz not null,
    capacity integer not null check (capacity > 0),
    published boolean not null default false,
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null,
    constraint check_dates check (end_at > start_at)
);

create index if not exists idx_events_college on public.events(college_id);
create index if not exists idx_events_published on public.events(published);
create index if not exists idx_events_dates on public.events(start_at, end_at);
create index if not exists idx_events_category on public.events(category);

-- ------------------------------------------------------------------------------
-- 4. REGISTRATIONS TABLE
-- ------------------------------------------------------------------------------
create table if not exists public.registrations (
    id uuid primary key default uuid_generate_v4(),
    event_id uuid not null references public.events(id) on delete cascade,
    student_id uuid not null references public.profiles(id) on delete cascade,
    status varchar(50) not null default 'registered' check (status in ('registered', 'cancelled', 'checked_in')),
    qr_token uuid unique not null default uuid_generate_v4(),
    checkin_at timestamptz,
    checked_in_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null,
    constraint uq_event_student unique (event_id, student_id)
);

create index if not exists idx_registrations_event on public.registrations(event_id);
create index if not exists idx_registrations_student on public.registrations(student_id);
create index if not exists idx_registrations_qr_token on public.registrations(qr_token);
create index if not exists idx_registrations_status on public.registrations(status);

-- ------------------------------------------------------------------------------
-- 5. AUTOMATIC PROFILE CREATION TRIGGER
-- ------------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger as $$
declare
    v_college_id uuid;
    v_full_name text;
begin
    v_college_id := null;
    if (new.raw_user_meta_data->>'college_id') is not null then
        begin
            v_college_id := (new.raw_user_meta_data->>'college_id')::uuid;
        exception when others then
            v_college_id := null;
        end;
    end if;

    v_full_name := coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1));

    insert into public.profiles (id, email, full_name, role, college_id)
    values (
        new.id,
        new.email,
        v_full_name,
        'student',
        v_college_id
    )
    on conflict (id) do update set
        email = excluded.email,
        full_name = coalesce(public.profiles.full_name, excluded.full_name),
        college_id = coalesce(public.profiles.college_id, excluded.college_id);

    return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ------------------------------------------------------------------------------
-- 6. ATOMIC CAPACITY-SAFE REGISTRATION FUNCTION
-- ------------------------------------------------------------------------------
create or replace function public.register_student(
    p_event_id uuid,
    p_student_id uuid
)
returns json as $$
declare
    v_event record;
    v_active_count integer;
    v_existing record;
    v_result record;
begin
    -- 1. Lock the event row for update to prevent simultaneous race conditions
    select id, college_id, title, capacity, published, start_at, end_at
    into v_event
    from public.events
    where id = p_event_id
    for update;

    if not found then
        return json_build_object('success', false, 'error', 'Event does not exist.');
    end if;

    if not v_event.published then
        return json_build_object('success', false, 'error', 'This event is not published or open for registration.');
    end if;

    if v_event.end_at < now() then
        return json_build_object('success', false, 'error', 'This event has already concluded.');
    end if;

    -- 2. Check existing registration
    select id, status, qr_token
    into v_existing
    from public.registrations
    where event_id = p_event_id and student_id = p_student_id;

    if found then
        if v_existing.status = 'registered' then
            return json_build_object(
                'success', false,
                'error', 'You are already registered for this event.',
                'registration_id', v_existing.id,
                'qr_token', v_existing.qr_token
            );
        elsif v_existing.status = 'checked_in' then
            return json_build_object('success', false, 'error', 'You have already checked in to this event.');
        end if;
    end if;

    -- 3. Check capacity against active registrations
    select count(*)
    into v_active_count
    from public.registrations
    where event_id = p_event_id
      and status in ('registered', 'checked_in');

    if v_active_count >= v_event.capacity then
        return json_build_object(
            'success', false,
            'error', 'Event is sold out. Capacity (' || v_event.capacity || ') has been reached.'
        );
    end if;

    -- 4. Insert or reactivate registration
    if v_existing.id is not null then
        update public.registrations
        set status = 'registered',
            qr_token = uuid_generate_v4(),
            checkin_at = null,
            checked_in_by = null,
            updated_at = now()
        where id = v_existing.id
        returning id, qr_token, status into v_result;
    else
        insert into public.registrations (event_id, student_id, status)
        values (p_event_id, p_student_id, 'registered')
        returning id, qr_token, status into v_result;
    end if;

    return json_build_object(
        'success', true,
        'message', 'Registration successful!',
        'registration_id', v_result.id,
        'qr_token', v_result.qr_token,
        'status', v_result.status,
        'event_title', v_event.title,
        'remaining_capacity', (v_event.capacity - (v_active_count + 1))
    );
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------------------------
-- 7. ATTENDANCE CHECK-IN FUNCTION
-- ------------------------------------------------------------------------------
create or replace function public.checkin_registration(
    p_qr_token uuid,
    p_admin_id uuid
)
returns json as $$
declare
    v_admin record;
    v_reg record;
    v_student record;
    v_event record;
begin
    -- 1. Validate Admin
    select id, role, college_id
    into v_admin
    from public.profiles
    where id = p_admin_id;

    if not found or (v_admin.role not in ('admin', 'superadmin')) then
        return json_build_object('success', false, 'error', 'Unauthorized: Admin role required for check-in.');
    end if;

    -- 2. Fetch and lock registration row
    select r.id, r.event_id, r.student_id, r.status, r.qr_token, r.checkin_at
    into v_reg
    from public.registrations r
    where r.qr_token = p_qr_token
    for update;

    if not found then
        return json_build_object('success', false, 'error', 'Invalid ticket or QR token not found.');
    end if;

    -- 3. Fetch Event and Student
    select id, title, college_id, start_at, venue
    into v_event
    from public.events
    where id = v_reg.event_id;

    select id, full_name, email
    into v_student
    from public.profiles
    where id = v_reg.student_id;

    -- 4. College Isolation Check
    if v_admin.role = 'admin' and v_admin.college_id != v_event.college_id then
        return json_build_object('success', false, 'error', 'Forbidden: You are not authorized to check in participants for other colleges.');
    end if;

    -- 5. Status checks
    if v_reg.status = 'checked_in' then
        return json_build_object(
            'success', false,
            'error', 'Already checked in!',
            'checkin_at', v_reg.checkin_at,
            'participant_name', v_student.full_name,
            'event_title', v_event.title
        );
    elsif v_reg.status = 'cancelled' then
        return json_build_object('success', false, 'error', 'Registration was cancelled. Ticket is invalid.');
    end if;

    -- 6. Perform Check-in
    update public.registrations
    set status = 'checked_in',
        checkin_at = now(),
        checked_in_by = p_admin_id,
        updated_at = now()
    where id = v_reg.id;

    return json_build_object(
        'success', true,
        'message', 'Participant check-in successful!',
        'registration_id', v_reg.id,
        'participant_name', v_student.full_name,
        'participant_email', v_student.email,
        'event_title', v_event.title,
        'checkin_at', now()
    );
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------------------------
-- 8. STATS HELPER FUNCTION
-- ------------------------------------------------------------------------------
create or replace function public.get_event_stats(p_event_id uuid)
returns json as $$
declare
    v_capacity integer;
    v_registered integer;
    v_checked_in integer;
begin
    select capacity into v_capacity from public.events where id = p_event_id;
    if not found then
        return null;
    end if;

    select count(*) into v_registered
    from public.registrations
    where event_id = p_event_id and status = 'registered';

    select count(*) into v_checked_in
    from public.registrations
    where event_id = p_event_id and status = 'checked_in';

    return json_build_object(
        'capacity', v_capacity,
        'registered_count', v_registered,
        'checked_in_count', v_checked_in,
        'total_active', (v_registered + v_checked_in),
        'remaining_seats', greatest(0, v_capacity - (v_registered + v_checked_in))
    );
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------------------------
-- 9. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------
alter table public.colleges enable row level security;
alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.registrations enable row level security;

create or replace function public.auth_user_role()
returns text as $$
    select role from public.profiles where id = auth.uid();
$$ language sql stable security definer;

create or replace function public.auth_user_college_id()
returns uuid as $$
    select college_id from public.profiles where id = auth.uid();
$$ language sql stable security definer;

-- Colleges
drop policy if exists "colleges_select_public" on public.colleges;
create policy "colleges_select_public" on public.colleges for select using (true);

drop policy if exists "colleges_superadmin_manage" on public.colleges;
create policy "colleges_superadmin_manage" on public.colleges for all
    using (public.auth_user_role() = 'superadmin')
    with check (public.auth_user_role() = 'superadmin');

-- Profiles
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles for select using (id = auth.uid());

drop policy if exists "profiles_select_college_admin" on public.profiles;
create policy "profiles_select_college_admin" on public.profiles for select
    using (public.auth_user_role() = 'admin' and college_id = public.auth_user_college_id());

drop policy if exists "profiles_select_superadmin" on public.profiles;
create policy "profiles_select_superadmin" on public.profiles for select
    using (public.auth_user_role() = 'superadmin');

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles for update
    using (id = auth.uid())
    with check (
        id = auth.uid()
        and role = (select role from public.profiles where id = auth.uid())
        and college_id is not distinct from (select college_id from public.profiles where id = auth.uid())
    );

drop policy if exists "profiles_update_superadmin" on public.profiles;
create policy "profiles_update_superadmin" on public.profiles for update
    using (public.auth_user_role() = 'superadmin');

-- Events
drop policy if exists "events_select_published" on public.events;
create policy "events_select_published" on public.events for select using (published = true);

drop policy if exists "events_select_college_admin" on public.events;
create policy "events_select_college_admin" on public.events for select
    using (public.auth_user_role() = 'admin' and college_id = public.auth_user_college_id());

drop policy if exists "events_select_superadmin" on public.events;
create policy "events_select_superadmin" on public.events for select
    using (public.auth_user_role() = 'superadmin');

drop policy if exists "events_insert_college_admin" on public.events;
create policy "events_insert_college_admin" on public.events for insert
    with check (
        public.auth_user_role() = 'admin'
        and college_id = public.auth_user_college_id()
    );

drop policy if exists "events_modify_college_admin" on public.events;
create policy "events_modify_college_admin" on public.events for update
    using (public.auth_user_role() = 'admin' and college_id = public.auth_user_college_id())
    with check (college_id = public.auth_user_college_id());

drop policy if exists "events_delete_college_admin" on public.events;
create policy "events_delete_college_admin" on public.events for delete
    using (public.auth_user_role() = 'admin' and college_id = public.auth_user_college_id());

-- Registrations
drop policy if exists "registrations_select_student" on public.registrations;
create policy "registrations_select_student" on public.registrations for select
    using (student_id = auth.uid());

drop policy if exists "registrations_select_college_admin" on public.registrations;
create policy "registrations_select_college_admin" on public.registrations for select
    using (
        public.auth_user_role() = 'admin'
        and event_id in (select id from public.events where college_id = public.auth_user_college_id())
    );

drop policy if exists "registrations_select_superadmin" on public.registrations;
create policy "registrations_select_superadmin" on public.registrations for select
    using (public.auth_user_role() = 'superadmin');

drop policy if exists "registrations_cancel_student" on public.registrations;
create policy "registrations_cancel_student" on public.registrations for update
    using (student_id = auth.uid())
    with check (student_id = auth.uid() and status in ('cancelled', 'registered'));

-- ------------------------------------------------------------------------------
-- 10. SEED INITIAL COLLEGES & SAMPLE EVENTS
-- ------------------------------------------------------------------------------
insert into public.colleges (id, identifier, name, location, website)
values 
(
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'mrecw',
    'Malla Reddy Engineering College for Women',
    'Maisammaguda, Secunderabad, Telangana',
    'https://www.mallareddyecw.com'
),
(
    'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22',
    'cbit',
    'Chaitanya Bharathi Institute of Technology',
    'Gandipet, Hyderabad, Telangana',
    'https://www.cbit.ac.in'
)
on conflict (identifier) do update set
    name = excluded.name,
    location = excluded.location,
    website = excluded.website;

insert into public.events (
    id, college_id, title, description, category, venue, 
    banner_url, start_at, end_at, capacity, published
) values
(
    'e0eebc99-9c0b-4ef8-bb6d-6bb9bd380e01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'FutureTech AI & Robotics Conclave 2026',
    'Explore breakthroughs in Generative AI, Autonomous Robotics, and Intelligent Systems with keynote addresses from industry leaders and live drone demonstrations.',
    'Technology',
    'Auditorium Block A, MRECW Campus',
    'https://images.unsplash.com/photo-1485827404703-89b55fcc595e?auto=format&fit=crop&w=800&q=80',
    now() + interval '3 days',
    now() + interval '3 days 4 hours',
    120,
    true
),
(
    'e0eebc99-9c0b-4ef8-bb6d-6bb9bd380e02',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'EmpowHer: Women in Engineering Summit',
    'A national panel discussion bringing together women pioneers in cybersecurity, aerospace, and startup ecosystems to mentor the next generation of engineers.',
    'Leadership',
    'Seminar Hall 2, MRECW Campus',
    'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&w=800&q=80',
    now() + interval '7 days',
    now() + interval '7 days 3 hours',
    80,
    true
),
(
    'e0eebc99-9c0b-4ef8-bb6d-6bb9bd380e03',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'CodeQuest 24-Hour National Hackathon',
    'Form teams of up to 4 participants to build real-world software solutions across Healthcare, Fintech, and Green Energy. Exciting prize pool and placement fast-tracks!',
    'Hackathon',
    'Advanced Computing Center, MRECW',
    'https://images.unsplash.com/photo-1504384308090-c894fdcc538d?auto=format&fit=crop&w=800&q=80',
    now() + interval '14 days',
    now() + interval '15 days',
    60,
    true
),
(
    'e0eebc99-9c0b-4ef8-bb6d-6bb9bd380e04',
    'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22',
    'SUDHEE: Annual Inter-College Technical Fest',
    'Flagship annual technical symposium with paper presentations, robowars, coding challenges, and innovation expos.',
    'Symposium',
    'Main Grounds, CBIT Campus',
    'https://images.unsplash.com/photo-1511578314322-379afb476865?auto=format&fit=crop&w=800&q=80',
    now() + interval '10 days',
    now() + interval '10 days 6 hours',
    200,
    true
)
on conflict (id) do nothing;

commit;


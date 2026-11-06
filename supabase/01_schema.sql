-- ==============================================================================
-- EVENTORA — DATABASE SCHEMA
-- File: supabase/01_schema.sql
-- Description: Core tables, foreign keys, constraints, and indexes.
-- ==============================================================================

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 1. COLLEGES TABLE
-- ------------------------------------------------------------------------------
create table if not exists public.colleges (
    id uuid primary key default uuid_generate_v4(),
    identifier varchar(50) unique not null,          -- e.g. 'mrecw'
    name varchar(255) not null,                     -- e.g. 'Malla Reddy Engineering College for Women'
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
-- Extends Supabase auth.users with college affiliation and role
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
    created_by uuid not null references public.profiles(id) on delete cascade,
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
    -- Prevent duplicate registrations for the same user and event
    constraint uq_event_student unique (event_id, student_id)
);

create index if not exists idx_registrations_event on public.registrations(event_id);
create index if not exists idx_registrations_student on public.registrations(student_id);
create index if not exists idx_registrations_qr_token on public.registrations(qr_token);
create index if not exists idx_registrations_status on public.registrations(status);

-- ------------------------------------------------------------------------------
-- 5. AUTOMATIC PROFILE CREATION TRIGGER
-- ------------------------------------------------------------------------------
-- Ensures that when an authenticated user signs up, their profile is initialized
-- with role = 'student' unless assigned explicitly by database admin.
create or replace function public.handle_new_user()
returns trigger as $$
declare
    v_college_id uuid;
    v_full_name text;
begin
    -- Extract college_id from metadata if passed, else fallback
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
        'student', -- Always force student on public signup to prevent role escalation
        v_college_id
    )
    on conflict (id) do update set
        email = excluded.email,
        full_name = coalesce(public.profiles.full_name, excluded.full_name),
        college_id = coalesce(public.profiles.college_id, excluded.college_id);

    return new;
end;
$$ language plpgsql security definer;

-- Drop and recreate auth trigger
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

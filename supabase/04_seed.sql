-- ==============================================================================
-- EVENTORA — INITIAL SEED DATA
-- File: supabase/04_seed.sql
-- Description: Initial colleges directory, sample events, and test data.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. SEED COLLEGES DIRECTORY
-- ------------------------------------------------------------------------------
-- Primary institution: Malla Reddy Engineering College for Women (MRECW)
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

-- ------------------------------------------------------------------------------
-- 2. SEED SAMPLE EVENTS (MRECW)
-- ------------------------------------------------------------------------------
-- Note: created_by will use the first profile found or a placeholder UUID.
-- If no profiles exist yet, we insert with a dummy UUID and update once an admin signs up.

do $$
declare
    v_mrecw_id uuid;
    v_cbit_id uuid;
    v_dummy_creator uuid := '00000000-0000-0000-0000-000000000000';
    v_actual_creator uuid;
begin
    select id into v_mrecw_id from public.colleges where identifier = 'mrecw';
    select id into v_cbit_id from public.colleges where identifier = 'cbit';

    -- Find first admin or user if one exists
    select id into v_actual_creator from public.profiles limit 1;
    if v_actual_creator is null then
        v_actual_creator := v_dummy_creator;
    end if;

    -- Only insert sample events if none exist
    if not exists (select 1 from public.events where college_id = v_mrecw_id) then
        insert into public.events (
            id, college_id, created_by, title, description, category, venue, 
            banner_url, start_at, end_at, capacity, published
        ) values
        (
            'e0eebc99-9c0b-4ef8-bb6d-6bb9bd380e01',
            v_mrecw_id,
            v_actual_creator,
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
            v_mrecw_id,
            v_actual_creator,
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
            v_mrecw_id,
            v_actual_creator,
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
            v_cbit_id,
            v_actual_creator,
            'SUDHEE: Annual Inter-College Technical Fest',
            'Flagship annual technical symposium with paper presentations, robowars, coding challenges, and innovation expos.',
            'Symposium',
            'Main Grounds, CBIT Campus',
            'https://images.unsplash.com/photo-1511578314322-379afb476865?auto=format&fit=crop&w=800&q=80',
            now() + interval '10 days',
            now() + interval '10 days 6 hours',
            200,
            true
        );
    end if;
end $$;

-- ------------------------------------------------------------------------------
-- 3. PROMOTING A USER TO COLLEGE ADMIN
-- ------------------------------------------------------------------------------
-- After creating an account in the UI (or in Supabase Auth), run this snippet in
-- the Supabase SQL editor to assign the admin role to your college admin email:
--
-- UPDATE public.profiles
-- SET role = 'admin',
--     college_id = (SELECT id FROM public.colleges WHERE identifier = 'mrecw')
-- WHERE email = 'your_admin_email@example.com';


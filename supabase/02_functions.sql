-- ==============================================================================
-- EVENTORA — DATABASE FUNCTIONS & PROCEDURES
-- File: supabase/02_functions.sql
-- Description: Concurrency-safe registration and attendance check-in functions.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. ATOMIC CAPACITY-SAFE REGISTRATION
-- ------------------------------------------------------------------------------
-- Uses SELECT ... FOR UPDATE on the events row to prevent race conditions during
-- concurrent registration attempts. Handles duplicate check and capacity limits.
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
    -- 1. Lock the event row for the duration of this transaction
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

    -- 2. Check existing registration for this student
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
        -- If cancelled, we can permit re-registration if capacity allows
    end if;

    -- 3. Calculate current active seats taken
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

    -- 4. Insert new registration or reactivate previously cancelled registration
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
-- 2. SECURE ATTENDANCE CHECK-IN FUNCTION
-- ------------------------------------------------------------------------------
-- Validates QR token, ensures college admin authorization match, and records check-in.
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
    -- 1. Validate Admin and permissions
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

    -- 3. Fetch Event and Student info
    select id, title, college_id, start_at, venue
    into v_event
    from public.events
    where id = v_reg.event_id;

    select id, full_name, email
    into v_student
    from public.profiles
    where id = v_reg.student_id;

    -- 4. Check College Isolation: Admin can only check-in for their own college
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
-- 3. EVENT CAPACITY AND STATS HELPER
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


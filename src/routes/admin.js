// src/routes/admin.js
const express = require('express');
const router = express.Router();
const Joi = require('joi');
const { supabaseAdmin } = require('../config');
const { authenticate, requireRole } = require('../middleware/auth');

// Apply authentication and admin role requirement to all routes in this file
router.use(authenticate, requireRole(['admin', 'superadmin']));

// Event validation schema
const eventSchema = Joi.object({
    title: Joi.string().trim().min(3).max(255).required(),
    description: Joi.string().trim().min(10).required(),
    category: Joi.string().trim().max(100).default('General'),
    venue: Joi.string().trim().max(255).required(),
    banner_url: Joi.string().uri().allow('', null).optional(),
    start_at: Joi.date().iso().required(),
    end_at: Joi.date().iso().greater(Joi.ref('start_at')).required().messages({
        'date.greater': 'End time must be after start time.'
    }),
    capacity: Joi.number().integer().min(1).max(50000).required(),
    published: Joi.boolean().default(false),
    college_id: Joi.string().uuid().optional() // Only superadmin may override
});

// ------------------------------------------------------------------------------
// 1. GET ALL EVENTS FOR ADMIN'S COLLEGE
// ------------------------------------------------------------------------------
router.get('/events', async (req, res, next) => {
    try {
        let query = supabaseAdmin
            .from('events')
            .select(`
                id,
                title,
                description,
                category,
                venue,
                banner_url,
                start_at,
                end_at,
                capacity,
                published,
                created_at,
                college_id,
                colleges (
                    id,
                    name,
                    identifier
                )
            `)
            .order('start_at', { ascending: true });

        // Normal admin can ONLY view events for their own assigned college
        if (req.user.role === 'admin') {
            if (!req.user.college_id) {
                return res.status(400).json({
                    success: false,
                    error: 'Your admin account has no college assigned. Please contact a superadmin.'
                });
            }
            query = query.eq('college_id', req.user.college_id);
        }

        const { data: events, error } = await query;
        if (error) throw error;

        // Fetch registration & check-in counts
        const eventIds = events.map(e => e.id);
        const statsMap = {};

        if (eventIds.length > 0) {
            const { data: regData } = await supabaseAdmin
                .from('registrations')
                .select('event_id, status')
                .in('event_id', eventIds);

            if (regData) {
                regData.forEach(r => {
                    if (!statsMap[r.event_id]) {
                        statsMap[r.event_id] = { registered: 0, checked_in: 0, cancelled: 0 };
                    }
                    if (r.status === 'registered') statsMap[r.event_id].registered++;
                    if (r.status === 'checked_in') statsMap[r.event_id].checked_in++;
                    if (r.status === 'cancelled') statsMap[r.event_id].cancelled++;
                });
            }
        }

        const enriched = events.map(ev => {
            const counts = statsMap[ev.id] || { registered: 0, checked_in: 0, cancelled: 0 };
            const activeCount = counts.registered + counts.checked_in;
            return {
                ...ev,
                stats: {
                    ...counts,
                    total_active: activeCount,
                    remaining_seats: Math.max(0, ev.capacity - activeCount)
                }
            };
        });

        return res.json({
            success: true,
            data: enriched
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 2. CREATE A NEW EVENT (Bound to Admin's College)
// ------------------------------------------------------------------------------
router.post('/events', async (req, res, next) => {
    try {
        const { error, value } = eventSchema.validate(req.body);
        if (error) return next(error);

        // Enforce College Isolation: Admin can only create for their own college
        let targetCollegeId = req.user.college_id;
        if (req.user.role === 'superadmin' && value.college_id) {
            targetCollegeId = value.college_id;
        }

        if (!targetCollegeId) {
            return res.status(400).json({
                success: false,
                error: 'Cannot create event: No college associated with your account.'
            });
        }

        const eventData = {
            college_id: targetCollegeId,
            created_by: req.user.id,
            title: value.title,
            description: value.description,
            category: value.category,
            venue: value.venue,
            banner_url: value.banner_url || null,
            start_at: value.start_at,
            end_at: value.end_at,
            capacity: value.capacity,
            published: value.published
        };

        const { data: newEvent, error: insertError } = await supabaseAdmin
            .from('events')
            .insert(eventData)
            .select()
            .single();

        if (insertError) throw insertError;

        return res.status(201).json({
            success: true,
            message: 'Event created successfully!',
            data: newEvent
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 3. UPDATE AN EVENT (With Isolation Check)
// ------------------------------------------------------------------------------
router.put('/events/:id', async (req, res, next) => {
    try {
        const { id } = req.params;
        const { error, value } = eventSchema.validate(req.body);
        if (error) return next(error);

        // Fetch existing event
        const { data: existing, error: fetchErr } = await supabaseAdmin
            .from('events')
            .select('id, college_id')
            .eq('id', id)
            .single();

        if (fetchErr || !existing) {
            return res.status(404).json({ success: false, error: 'Event not found.' });
        }

        // Ownership enforcement
        if (req.user.role === 'admin' && existing.college_id !== req.user.college_id) {
            return res.status(403).json({
                success: false,
                error: 'Forbidden: You cannot modify an event belonging to another college.'
            });
        }

        const updateData = {
            title: value.title,
            description: value.description,
            category: value.category,
            venue: value.venue,
            banner_url: value.banner_url || null,
            start_at: value.start_at,
            end_at: value.end_at,
            capacity: value.capacity,
            published: value.published,
            updated_at: new Date().toISOString()
        };

        const { data: updated, error: updateErr } = await supabaseAdmin
            .from('events')
            .update(updateData)
            .eq('id', id)
            .select()
            .single();

        if (updateErr) throw updateErr;

        return res.json({
            success: true,
            message: 'Event updated successfully.',
            data: updated
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 4. DELETE AN EVENT
// ------------------------------------------------------------------------------
router.delete('/events/:id', async (req, res, next) => {
    try {
        const { id } = req.params;

        const { data: existing, error: fetchErr } = await supabaseAdmin
            .from('events')
            .select('id, college_id')
            .eq('id', id)
            .single();

        if (fetchErr || !existing) {
            return res.status(404).json({ success: false, error: 'Event not found.' });
        }

        if (req.user.role === 'admin' && existing.college_id !== req.user.college_id) {
            return res.status(403).json({
                success: false,
                error: 'Forbidden: You cannot delete an event belonging to another college.'
            });
        }

        const { error: delErr } = await supabaseAdmin
            .from('events')
            .delete()
            .eq('id', id);

        if (delErr) throw delErr;

        return res.json({
            success: true,
            message: 'Event deleted successfully.'
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 5. GET PARTICIPANT ROSTER FOR AN EVENT
// ------------------------------------------------------------------------------
router.get('/events/:id/participants', async (req, res, next) => {
    try {
        const { id } = req.params;

        const { data: event, error: eventErr } = await supabaseAdmin
            .from('events')
            .select('id, title, college_id, capacity')
            .eq('id', id)
            .single();

        if (eventErr || !event) {
            return res.status(404).json({ success: false, error: 'Event not found.' });
        }

        if (req.user.role === 'admin' && event.college_id !== req.user.college_id) {
            return res.status(403).json({
                success: false,
                error: 'Forbidden: You cannot view participants for another college.'
            });
        }

        const { data: participants, error: partErr } = await supabaseAdmin
            .from('registrations')
            .select(`
                id,
                status,
                qr_token,
                checkin_at,
                created_at,
                profiles (
                    id,
                    email,
                    full_name
                )
            `)
            .eq('event_id', id)
            .order('created_at', { ascending: false });

        if (partErr) throw partErr;

        return res.json({
            success: true,
            event: {
                id: event.id,
                title: event.title,
                capacity: event.capacity
            },
            count: participants.length,
            data: participants
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 6. COLLEGE STATS OVERVIEW
// ------------------------------------------------------------------------------
router.get('/stats', async (req, res, next) => {
    try {
        let collegeId = req.user.college_id;

        if (req.user.role === 'admin' && !collegeId) {
            return res.status(400).json({ success: false, error: 'Admin has no college associated.' });
        }

        // Fetch events count
        let eventsQuery = supabaseAdmin.from('events').select('id, capacity', { count: 'exact' });
        if (req.user.role === 'admin') {
            eventsQuery = eventsQuery.eq('college_id', collegeId);
        }
        const { data: eventsList, count: eventsCount } = await eventsQuery;

        const eventIds = (eventsList || []).map(e => e.id);

        let totalRegistrations = 0;
        let totalCheckedIn = 0;

        if (eventIds.length > 0) {
            const { data: regList } = await supabaseAdmin
                .from('registrations')
                .select('status')
                .in('event_id', eventIds);

            if (regList) {
                totalRegistrations = regList.filter(r => r.status === 'registered' || r.status === 'checked_in').length;
                totalCheckedIn = regList.filter(r => r.status === 'checked_in').length;
            }
        }

        return res.json({
            success: true,
            stats: {
                total_events: eventsCount || 0,
                total_registrations: totalRegistrations,
                total_checked_in: totalCheckedIn,
                attendance_rate: totalRegistrations > 0 ? Math.round((totalCheckedIn / totalRegistrations) * 100) : 0
            }
        });
    } catch (err) {
        next(err);
    }
});

module.exports = router;


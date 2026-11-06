// src/routes/events.js
const express = require('express');
const router = express.Router();
const { supabaseAnon, supabaseAdmin } = require('../config');

// ------------------------------------------------------------------------------
// 1. PUBLIC: LIST EVENTS (With search, filters, and real-time capacity)
// ------------------------------------------------------------------------------
router.get('/', async (req, res, next) => {
    try {
        const { search, college, category } = req.query;

        let query = supabaseAnon
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
                college_id,
                colleges (
                    id,
                    identifier,
                    name,
                    location
                )
            `)
            .eq('published', true)
            .order('start_at', { ascending: true });

        // Filter by college identifier or UUID
        if (college && college !== 'all') {
            // Check if uuid or identifier
            const isUuid = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(college);
            if (isUuid) {
                query = query.eq('college_id', college);
            } else {
                // Look up college ID by identifier
                const { data: colData } = await supabaseAnon
                    .from('colleges')
                    .select('id')
                    .eq('identifier', college.toLowerCase())
                    .single();

                if (colData) {
                    query = query.eq('college_id', colData.id);
                }
            }
        }

        // Filter by category
        if (category && category !== 'all') {
            query = query.ilike('category', category);
        }

        // Search by keyword in title or description
        if (search && search.trim()) {
            const term = `%${search.trim()}%`;
            query = query.or(`title.ilike.${term},description.ilike.${term},venue.ilike.${term}`);
        }

        const { data: events, error } = await query;
        if (error) throw error;

        // Fetch seat counts for all retrieved events to display live capacity
        const eventIds = events.map(e => e.id);
        let registrationCounts = {};

        if (eventIds.length > 0) {
            const { data: counts, error: countErr } = await supabaseAdmin
                .from('registrations')
                .select('event_id, status')
                .in('event_id', eventIds)
                .in('status', ['registered', 'checked_in']);

            if (!countErr && counts) {
                counts.forEach(row => {
                    registrationCounts[row.event_id] = (registrationCounts[row.event_id] || 0) + 1;
                });
            }
        }

        // Augment each event with registered_count and remaining_seats
        const enrichedEvents = events.map(event => {
            const registered = registrationCounts[event.id] || 0;
            const remaining = Math.max(0, event.capacity - registered);
            return {
                ...event,
                registered_count: registered,
                remaining_seats: remaining,
                is_sold_out: remaining === 0
            };
        });

        return res.json({
            success: true,
            count: enrichedEvents.length,
            data: enrichedEvents
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 2. PUBLIC: GET SINGLE EVENT DETAILS
// ------------------------------------------------------------------------------
router.get('/:id', async (req, res, next) => {
    try {
        const { id } = req.params;

        const { data: event, error } = await supabaseAnon
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
                    identifier,
                    name,
                    location,
                    website
                )
            `)
            .eq('id', id)
            .single();

        if (error || !event) {
            return res.status(404).json({
                success: false,
                error: 'Event not found.'
            });
        }

        // Get live stats via RPC or query
        const { data: stats } = await supabaseAdmin.rpc('get_event_stats', { p_event_id: id });

        return res.json({
            success: true,
            data: {
                ...event,
                stats: stats || {
                    capacity: event.capacity,
                    registered_count: 0,
                    remaining_seats: event.capacity,
                    is_sold_out: false
                }
            }
        });
    } catch (err) {
        next(err);
    }
});

module.exports = router;


// src/routes/registrations.js
const express = require('express');
const router = express.Router();
const Joi = require('joi');
const { supabaseAdmin } = require('../config');
const { authenticate, requireRole } = require('../middleware/auth');
const { generateTicketQR } = require('../utils/qr');

// ------------------------------------------------------------------------------
// 1. REGISTER FOR AN EVENT (Capacity-Safe RPC)
// ------------------------------------------------------------------------------
router.post('/', authenticate, async (req, res, next) => {
    try {
        const schema = Joi.object({
            event_id: Joi.string().uuid().required().messages({
                'any.required': 'Event ID is required.',
                'string.uuid': 'Invalid Event ID format.'
            })
        });

        const { error, value } = schema.validate(req.body);
        if (error) return next(error);

        const { event_id } = value;
        const student_id = req.user.id;

        // Execute atomic registration function inside Supabase
        const { data: rpcResult, error: rpcError } = await supabaseAdmin.rpc('register_student', {
            p_event_id: event_id,
            p_student_id: student_id
        });

        if (rpcError) {
            console.error('RPC register_student error:', rpcError);
            return res.status(400).json({
                success: false,
                error: rpcError.message || 'Registration failed.'
            });
        }

        if (!rpcResult.success) {
            return res.status(400).json({
                success: false,
                error: rpcResult.error,
                details: rpcResult
            });
        }

        // Generate QR code data URL for the new ticket token
        let qrDataUrl = null;
        if (rpcResult.qr_token) {
            qrDataUrl = await generateTicketQR(rpcResult.qr_token);
        }

        return res.status(201).json({
            success: true,
            message: rpcResult.message,
            registration_id: rpcResult.registration_id,
            qr_token: rpcResult.qr_token,
            qr_image: qrDataUrl,
            status: rpcResult.status,
            event_title: rpcResult.event_title
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 2. GET CURRENT STUDENT'S REGISTRATION HISTORY & TICKETS
// ------------------------------------------------------------------------------
router.get('/my', authenticate, async (req, res, next) => {
    try {
        const student_id = req.user.id;

        const { data: registrations, error } = await supabaseAdmin
            .from('registrations')
            .select(`
                id,
                status,
                qr_token,
                checkin_at,
                created_at,
                events (
                    id,
                    title,
                    description,
                    category,
                    venue,
                    banner_url,
                    start_at,
                    end_at,
                    colleges (
                        id,
                        name,
                        identifier
                    )
                )
            `)
            .eq('student_id', student_id)
            .order('created_at', { ascending: false });

        if (error) throw error;

        // Attach QR data URL to each active ticket
        const enriched = await Promise.all(registrations.map(async (reg) => {
            let qrImage = null;
            if (reg.status === 'registered' && reg.qr_token) {
                try {
                    qrImage = await generateTicketQR(reg.qr_token);
                } catch (e) {
                    // Ignore QR generation failure for list display
                }
            }
            return {
                ...reg,
                qr_image: qrImage
            };
        }));

        return res.json({
            success: true,
            count: enriched.length,
            data: enriched
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 3. CANCEL REGISTRATION
// ------------------------------------------------------------------------------
router.delete('/:id', authenticate, async (req, res, next) => {
    try {
        const { id } = req.params;
        const student_id = req.user.id;

        // Verify registration exists and belongs to this student
        const { data: reg, error: fetchErr } = await supabaseAdmin
            .from('registrations')
            .select('id, status, event_id, student_id')
            .eq('id', id)
            .single();

        if (fetchErr || !reg) {
            return res.status(404).json({ success: false, error: 'Registration not found.' });
        }

        if (reg.student_id !== student_id && req.user.role !== 'superadmin') {
            return res.status(403).json({ success: false, error: 'You can only cancel your own registrations.' });
        }

        if (reg.status === 'checked_in') {
            return res.status(400).json({ success: false, error: 'Cannot cancel a ticket that has already been checked in.' });
        }

        if (reg.status === 'cancelled') {
            return res.status(400).json({ success: false, error: 'Registration is already cancelled.' });
        }

        const { error: updateErr } = await supabaseAdmin
            .from('registrations')
            .update({
                status: 'cancelled',
                updated_at: new Date().toISOString()
            })
            .eq('id', id);

        if (updateErr) throw updateErr;

        return res.json({
            success: true,
            message: 'Registration cancelled successfully. Seat has been released.'
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 4. ATTENDANCE CHECK-IN (Admin Only)
// ------------------------------------------------------------------------------
router.post('/checkin', authenticate, requireRole(['admin', 'superadmin']), async (req, res, next) => {
    try {
        const schema = Joi.object({
            qr_token: Joi.string().uuid().required().messages({
                'any.required': 'QR token is required.',
                'string.uuid': 'Invalid QR token format.'
            })
        });

        const { error, value } = schema.validate(req.body);
        if (error) return next(error);

        const { qr_token } = value;
        const admin_id = req.user.id;

        // Call stored check-in procedure
        const { data: result, error: rpcError } = await supabaseAdmin.rpc('checkin_registration', {
            p_qr_token: qr_token,
            p_admin_id: admin_id
        });

        if (rpcError) {
            console.error('Check-in RPC error:', rpcError);
            return res.status(400).json({ success: false, error: rpcError.message || 'Check-in failed.' });
        }

        if (!result.success) {
            return res.status(400).json({
                success: false,
                error: result.error,
                details: result
            });
        }

        return res.json({
            success: true,
            message: result.message,
            participant: {
                name: result.participant_name,
                email: result.participant_email,
                event: result.event_title,
                checkin_at: result.checkin_at
            }
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 5. TICKET TOKEN VERIFICATION PREVIEW (Admin Only)
// ------------------------------------------------------------------------------
router.get('/preview/:token', authenticate, requireRole(['admin', 'superadmin']), async (req, res, next) => {
    try {
        const { token } = req.params;

        const { data: reg, error } = await supabaseAdmin
            .from('registrations')
            .select(`
                id,
                status,
                checkin_at,
                created_at,
                events (
                    id,
                    title,
                    venue,
                    start_at,
                    college_id
                ),
                profiles (
                    id,
                    full_name,
                    email
                )
            `)
            .eq('qr_token', token)
            .single();

        if (error || !reg) {
            return res.status(404).json({ success: false, error: 'Ticket token not recognized.' });
        }

        // Check college isolation
        if (req.user.role === 'admin' && req.user.college_id !== reg.events.college_id) {
            return res.status(403).json({
                success: false,
                error: 'Ticket belongs to another college. You cannot verify or check in this participant.'
            });
        }

        return res.json({
            success: true,
            data: reg
        });
    } catch (err) {
        next(err);
    }
});

module.exports = router;


// src/routes/auth.js
const express = require('express');
const router = express.Router();
const Joi = require('joi');
const { supabaseAnon, supabaseAdmin } = require('../config');
const { authenticate } = require('../middleware/auth');

// Validation schemas
const signupSchema = Joi.object({
    email: Joi.string().email().required().messages({
        'string.email': 'Please provide a valid email address.',
        'any.required': 'Email is required.'
    }),
    password: Joi.string().min(6).required().messages({
        'string.min': 'Password must be at least 6 characters long.',
        'any.required': 'Password is required.'
    }),
    full_name: Joi.string().trim().min(2).max(100).required().messages({
        'any.required': 'Full name is required.'
    }),
    college_id: Joi.string().uuid().allow(null, '').optional()
});

const loginSchema = Joi.object({
    email: Joi.string().email().required(),
    password: Joi.string().required()
});

// ------------------------------------------------------------------------------
// 1. PUBLIC: GET ALL COLLEGES (For dropdowns and discovery)
// ------------------------------------------------------------------------------
router.get('/colleges', async (req, res, next) => {
    try {
        const { data, error } = await supabaseAnon
            .from('colleges')
            .select('id, identifier, name, location, website')
            .order('name', { ascending: true });

        if (error) throw error;

        return res.json({
            success: true,
            data
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 2. SIGN UP (Student)
// ------------------------------------------------------------------------------
router.post('/signup', async (req, res, next) => {
    try {
        const { error, value } = signupSchema.validate(req.body);
        if (error) return next(error);

        const { email, password, full_name, college_id } = value;

        // Register user via Supabase Auth
        // Role is strictly forced to 'student' to prevent self-elevation
        const { data: authData, error: authError } = await supabaseAnon.auth.signUp({
            email,
            password,
            options: {
                data: {
                    full_name,
                    college_id: college_id || null,
                    role: 'student'
                }
            }
        });

        if (authError) {
            return res.status(400).json({
                success: false,
                error: authError.message
            });
        }

        // Ensure profile row exists
        if (authData.user) {
            const { error: upsertError } = await supabaseAdmin
                .from('profiles')
                .upsert({
                    id: authData.user.id,
                    email: authData.user.email,
                    full_name,
                    role: 'student',
                    college_id: college_id || null
                });

            if (upsertError) {
                console.error('Profile upsert warning:', upsertError);
            }
        }

        return res.status(201).json({
            success: true,
            message: 'Account created successfully! You can now sign in.',
            session: authData.session,
            user: {
                id: authData.user.id,
                email: authData.user.email,
                full_name,
                role: 'student'
            }
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 3. SIGN IN
// ------------------------------------------------------------------------------
router.post('/login', async (req, res, next) => {
    try {
        const { error, value } = loginSchema.validate(req.body);
        if (error) return next(error);

        const { email, password } = value;

        const { data: authData, error: authError } = await supabaseAnon.auth.signInWithPassword({
            email,
            password
        });

        if (authError || !authData.session) {
            return res.status(401).json({
                success: false,
                error: authError?.message || 'Invalid email or password.'
            });
        }

        // Fetch user's profile and college
        const { data: profile } = await supabaseAdmin
            .from('profiles')
            .select('id, email, full_name, role, college_id, colleges(id, name, identifier)')
            .eq('id', authData.user.id)
            .single();

        return res.json({
            success: true,
            message: 'Signed in successfully.',
            access_token: authData.session.access_token,
            user: {
                id: authData.user.id,
                email: authData.user.email,
                full_name: profile?.full_name || authData.user.user_metadata?.full_name || email.split('@')[0],
                role: profile?.role || 'student',
                college_id: profile?.college_id || null,
                college: profile?.colleges || null
            }
        });
    } catch (err) {
        next(err);
    }
});

// ------------------------------------------------------------------------------
// 4. GET CURRENT AUTHENTICATED USER
// ------------------------------------------------------------------------------
router.get('/me', authenticate, async (req, res) => {
    return res.json({
        success: true,
        user: req.user
    });
});

module.exports = router;


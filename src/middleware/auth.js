// src/middleware/auth.js
const { supabaseAdmin, createUserScopedClient } = require('../config');

/**
 * Validates Supabase JWT from Authorization: Bearer <token>
 * Attaches user object and profile to req.user
 */
async function authenticate(req, res, next) {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({
                success: false,
                error: 'Authentication required. Please sign in.'
            });
        }

        const token = authHeader.split(' ')[1];
        if (!token) {
            return res.status(401).json({ success: false, error: 'Malformed authorization token.' });
        }

        // Verify token against Supabase Auth
        const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(token);

        if (authError || !authData.user) {
            return res.status(401).json({
                success: false,
                error: 'Invalid or expired session. Please sign in again.'
            });
        }

        const authUser = authData.user;

        // Fetch user profile from public.profiles
        const { data: profile, error: profileError } = await supabaseAdmin
            .from('profiles')
            .select('id, email, full_name, role, college_id, colleges(id, name, identifier)')
            .eq('id', authUser.id)
            .single();

        if (profileError && profileError.code !== 'PGRST116') {
            console.error('Error fetching user profile:', profileError);
        }

        req.token = token;
        req.user = {
            id: authUser.id,
            email: authUser.email,
            full_name: profile?.full_name || authUser.user_metadata?.full_name || authUser.email.split('@')[0],
            role: profile?.role || 'student',
            college_id: profile?.college_id || null,
            college: profile?.colleges || null
        };

        // Attach user-scoped client so queries automatically evaluate RLS using auth.uid()
        req.supabase = createUserScopedClient(token);

        next();
    } catch (err) {
        console.error('Auth middleware exception:', err);
        return res.status(500).json({ success: false, error: 'Internal authentication error.' });
    }
}

/**
 * Role-based authorization middleware
 * @param {string[]} allowedRoles - Array of permitted roles (e.g. ['admin', 'superadmin'])
 */
function requireRole(allowedRoles) {
    return (req, res, next) => {
        if (!req.user) {
            return res.status(401).json({ success: false, error: 'Unauthorized.' });
        }

        if (!allowedRoles.includes(req.user.role)) {
            return res.status(403).json({
                success: false,
                error: `Access denied. Requires one of: [${allowedRoles.join(', ')}]. Current role: '${req.user.role}'.`
            });
        }

        next();
    };
}

module.exports = {
    authenticate,
    requireRole
};

